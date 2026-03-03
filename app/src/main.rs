use std::env;
use std::fs;
use std::io::{Read, Write};
use std::path::PathBuf;

use ashpd::desktop::secret::Secret;
use sha2::{Digest, Sha256};

#[derive(Debug, Clone, Copy, PartialEq)]
enum Backend {
    Flatpak,
    Snap,
    Systemd,
}

impl Backend {
    fn as_str(&self) -> &'static str {
        match self {
            Backend::Flatpak => "flatpak",
            Backend::Snap => "snap",
            Backend::Systemd => "systemd",
        }
    }

    fn from_str(s: &str) -> Option<Backend> {
        match s {
            "flatpak" => Some(Backend::Flatpak),
            "snap" => Some(Backend::Snap),
            "systemd" => Some(Backend::Systemd),
            _ => None,
        }
    }
}

// --- 1. Environment Detection ---

fn detect_backend() -> Option<Backend> {
    if std::path::Path::new("/.flatpak-info").exists() {
        Some(Backend::Flatpak)
    } else if env::var("SNAP_DATA").is_ok() {
        Some(Backend::Snap)
    } else if env::var("CREDENTIALS_DIRECTORY").is_ok() {
        Some(Backend::Systemd)
    } else {
        None
    }
}

// --- Lockfile paths ---

fn lockfile_path_for(backend: &Backend) -> PathBuf {
    match backend {
        Backend::Snap => {
            let snap_data = env::var("SNAP_DATA").expect("SNAP_DATA not set");
            PathBuf::from(snap_data).join("access-keys.lock")
        }
        Backend::Flatpak => {
            // Inside flatpak sandbox, use app data dir
            let home = env::var("HOME").expect("HOME not set");
            PathBuf::from(home)
                .join(".var/app/org.example.access-keys/access-keys.lock")
        }
        Backend::Systemd => {
            PathBuf::from("/var/lib/access-keys/access-keys.lock")
        }
    }
}

fn hash_path_for(backend: &Backend) -> PathBuf {
    match backend {
        Backend::Snap => {
            let snap_data = env::var("SNAP_DATA").expect("SNAP_DATA not set");
            PathBuf::from(snap_data).join("access-keys.hash")
        }
        Backend::Flatpak => {
            let home = env::var("HOME").expect("HOME not set");
            PathBuf::from(home)
                .join(".var/app/org.example.access-keys/access-keys.hash")
        }
        Backend::Systemd => {
            // CREDENTIALS_DIRECTORY is read-only (populated by PID 1) and ephemeral,
            // so we store the hash alongside the lockfile in /var/lib/access-keys/
            PathBuf::from("/var/lib/access-keys/access-keys.hash")
        }
    }
}

fn compute_hash(data: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data);
    format!("{:x}", hasher.finalize())
}

// --- 2. Bootstrap ---

fn store_hash(backend: &Backend, hash: &str) -> Result<(), Box<dyn std::error::Error>> {
    let path = hash_path_for(backend);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(&path, hash)?;
    Ok(())
}

fn retrieve_hash(backend: &Backend) -> Result<String, Box<dyn std::error::Error>> {
    let path = hash_path_for(backend);
    let hash = fs::read_to_string(&path)?;
    Ok(hash)
}

fn bootstrap(backend: Backend) -> Result<(), Box<dyn std::error::Error>> {
    let lockfile_path = lockfile_path_for(&backend);
    let contents = format!("backend={}\n", backend.as_str());

    if let Some(parent) = lockfile_path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(&lockfile_path, &contents)?;

    let hash = compute_hash(contents.as_bytes());
    store_hash(&backend, &hash)?;

    eprintln!("Bootstrapped with backend: {}", backend.as_str());
    Ok(())
}

// --- 3. Normal Operation ---

fn read_lockfile_for_backend(backend: &Backend) -> Option<String> {
    let path = lockfile_path_for(backend);
    fs::read_to_string(&path).ok()
}

fn parse_backend_from_lockfile(contents: &str) -> Option<Backend> {
    for line in contents.lines() {
        if let Some(value) = line.strip_prefix("backend=") {
            return Backend::from_str(value.trim());
        }
    }
    None
}

/// Try to find an existing lockfile by checking all possible backend paths
fn find_existing_lockfile() -> Option<(Backend, String)> {
    // Check based on current environment first
    if let Some(detected) = detect_backend() {
        if let Some(contents) = read_lockfile_for_backend(&detected) {
            if let Some(locked) = parse_backend_from_lockfile(&contents) {
                return Some((locked, contents));
            }
        }
    }
    None
}

async fn run_flatpak_storage() -> Result<(), Box<dyn std::error::Error>> {
    use std::os::fd::AsFd;
    use tokio::net::UnixStream;
    use tokio::io::AsyncReadExt;

    let secret_proxy = Secret::new().await?;

    let (mut read_end, write_end) = UnixStream::pair()?;

    secret_proxy.retrieve(&write_end.as_fd()).await?;
    drop(write_end);

    let mut secret_bytes = Vec::new();
    read_end.read_to_end(&mut secret_bytes).await?;

    if !secret_bytes.is_empty() {
        let hex_str: String = secret_bytes.iter()
            .take(20)
            .map(|b| format!("{:02x}", b))
            .collect();
        println!("Secret read from Flatpak Portal: {} ({} bytes total)",
                 &hex_str[..hex_str.len().min(40)], secret_bytes.len());
    } else {
        return Err("No secret data received from portal".into());
    }

    Ok(())
}

fn run_snap_storage() -> Result<(), Box<dyn std::error::Error>> {
    let snap_data = env::var("SNAP_DATA")
        .map_err(|_| "SNAP_DATA environment variable not set")?;

    let secret_file = PathBuf::from(snap_data).join("secret.bin");

    if !secret_file.exists() {
        let mut file = fs::File::create(&secret_file)?;
        file.write_all(b"Stored secret")?;
        println!("Secret created");
    } else {
        let mut file = fs::File::open(&secret_file)?;
        let mut buffer = vec![0u8; 64];
        let bytes_read = file.read(&mut buffer)?;

        let secret = String::from_utf8_lossy(&buffer[..bytes_read]);
        let display_secret = if secret.len() > 20 {
            &secret[..20]
        } else {
            &secret
        };
        println!("Secret read from SNAP_DATA: {}", display_secret);
    }

    Ok(())
}

fn run_systemd_storage() -> Result<(), Box<dyn std::error::Error>> {
    let creds_dir = env::var("CREDENTIALS_DIRECTORY")
        .map_err(|_| "CREDENTIALS_DIRECTORY environment variable not set")?;

    let secret_file = PathBuf::from(creds_dir).join("sync-key");

    let mut file = fs::File::open(&secret_file)?;
    let mut buffer = Vec::new();
    file.read_to_end(&mut buffer)?;

    if buffer.is_empty() {
        return Err("Secret file is empty".into());
    }

    let secret = String::from_utf8_lossy(&buffer);
    let display_secret = if secret.len() > 20 {
        &secret[..20]
    } else {
        &secret
    };
    println!("Secret read from CREDENTIALS_DIRECTORY: {}", display_secret);

    Ok(())
}

async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let (backend, lockfile_contents) = match find_existing_lockfile() {
        Some(v) => v,
        None => {
            // No lockfile: first-run bootstrap
            let backend = detect_backend()
                .ok_or("No secure storage backend detected")?;
            bootstrap(backend)?;
            // Read back the lockfile we just wrote
            let contents = read_lockfile_for_backend(&backend)
                .ok_or("Failed to read lockfile after bootstrap")?;
            let locked = parse_backend_from_lockfile(&contents)
                .ok_or("Failed to parse lockfile after bootstrap")?;
            (locked, contents)
        }
    };

    let stored_hash = retrieve_hash(&backend)?;
    let actual_hash = compute_hash(lockfile_contents.as_bytes());

    if stored_hash != actual_hash {
        return Err("Lockfile integrity check failed. Run with --reset to re-initialize.".into());
    }

    match backend {
        Backend::Flatpak => run_flatpak_storage().await?,
        Backend::Snap => run_snap_storage()?,
        Backend::Systemd => run_systemd_storage()?,
    }

    Ok(())
}

#[tokio::main(flavor = "current_thread")]
async fn main() {
    let args: Vec<String> = env::args().collect();

    if args.iter().any(|a| a == "--backend") {
        match find_existing_lockfile() {
            Some((backend, _)) => {
                println!("{}", backend.as_str());
            }
            None => {
                eprintln!("No lockfile found. Run the application first to bootstrap.");
                std::process::exit(1);
            }
        }
        return;
    }

    if args.iter().any(|a| a == "--reset") {
        let backend = match detect_backend() {
            Some(b) => b,
            None => {
                eprintln!("No secure storage backend detected");
                std::process::exit(1);
            }
        };
        match bootstrap(backend) {
            Ok(_) => {
                println!("Reset complete. Backend: {}", backend.as_str());
            }
            Err(e) => {
                eprintln!("Error during reset: {}", e);
                std::process::exit(1);
            }
        }
        return;
    }

    match run().await {
        Ok(_) => {}
        Err(e) => {
            eprintln!("Error: {}", e);
            std::process::exit(1);
        }
    }
}

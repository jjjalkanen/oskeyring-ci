#[cfg(feature = "snap")]
use std::fs;
#[cfg(feature = "snap")]
use std::path::PathBuf;
#[cfg(feature = "snap")]
use std::io::{Read, Write};

#[cfg(feature = "flatpak")]
use ashpd::desktop::secret::Secret;

#[cfg(feature = "flatpak")]
async fn run_flatpak_storage() -> Result<(), Box<dyn std::error::Error>> {
    use std::os::fd::AsFd;
    use tokio::net::UnixStream;
    use tokio::io::AsyncReadExt;

    // The Secret Portal provides a per-application master secret
    // This secret is automatically generated and persisted by the portal
    let secret_proxy = Secret::new().await?;

    // Create a Unix socket pair to receive the secret
    let (mut read_end, write_end) = UnixStream::pair()?;

    // Request the secret from the portal (it writes to write_end)
    secret_proxy.retrieve(&write_end.as_fd()).await?;
    drop(write_end); // Close write end so read_end gets EOF

    // Read the secret from read_end
    let mut secret_bytes = Vec::new();
    read_end.read_to_end(&mut secret_bytes).await?;

    if !secret_bytes.is_empty() {
        // Display first 20 bytes as hex for consistency
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

#[cfg(feature = "snap")]
fn run_snap_storage() -> Result<(), Box<dyn std::error::Error>> {
    // Get SNAP_DATA environment variable
    let snap_data = std::env::var("SNAP_DATA")
        .map_err(|_| "SNAP_DATA environment variable not set")?;

    let secret_file = PathBuf::from(snap_data).join("secret.bin");

    // Check if secret file exists
    if !secret_file.exists() {
        // First run: create the secret
        let mut file = fs::File::create(&secret_file)?;
        file.write_all(b"Stored secret")?;
        println!("Secret created");
    } else {
        // Subsequent runs: read the secret back
        let mut file = fs::File::open(&secret_file)?;
        let mut buffer = vec![0u8; 64];
        let bytes_read = file.read(&mut buffer)?;

        let secret = String::from_utf8_lossy(&buffer[..bytes_read]);
        // Print up to 20 characters like the plan specified
        let display_secret = if secret.len() > 20 {
            &secret[..20]
        } else {
            &secret
        };
        println!("Secret read from SNAP_DATA: {}", display_secret);
    }

    Ok(())
}

#[cfg(feature = "flatpak")]
#[tokio::main(flavor = "current_thread")]
async fn main() {
    match run_flatpak_storage().await {
        Ok(_) => {},
        Err(e) => {
            eprintln!("Error accessing Flatpak secret storage: {}", e);
            std::process::exit(1);
        }
    }
}

#[cfg(all(not(feature = "flatpak"), feature = "snap"))]
fn main() {
    match run_snap_storage() {
        Ok(_) => {},
        Err(e) => {
            eprintln!("Error accessing snap storage: {}", e);
            std::process::exit(1);
        }
    }
}

#[cfg(all(not(feature = "flatpak"), not(feature = "snap")))]
fn main() {
    println!("All good");
}

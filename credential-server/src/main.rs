use std::collections::HashMap;
use std::env;
use std::fs;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::os::unix::net::UnixListener;
use std::path::PathBuf;
use std::time::{Duration, Instant};

use zeroize::Zeroizing;

fn peer_exe(pid: u32) -> std::io::Result<PathBuf> {
    let path = fs::read_link(format!("/proc/{}/exe", pid))?;
    let path_str = path.to_string_lossy();
    if path_str.ends_with(" (deleted)") {
        return Ok(PathBuf::from(&path_str[..path_str.len() - 10]));
    }
    Ok(path)
}

fn peer_cred(stream: &std::os::unix::net::UnixStream) -> std::io::Result<libc::ucred> {
    use std::os::unix::io::AsRawFd;
    let fd = stream.as_raw_fd();
    let mut cred: libc::ucred = unsafe { std::mem::zeroed() };
    let mut len = std::mem::size_of::<libc::ucred>() as libc::socklen_t;
    let ret = unsafe {
        libc::getsockopt(
            fd,
            libc::SOL_SOCKET,
            libc::SO_PEERCRED,
            &mut cred as *mut _ as *mut libc::c_void,
            &mut len,
        )
    };
    if ret != 0 {
        return Err(std::io::Error::last_os_error());
    }
    Ok(cred)
}

fn main() {
    // Prevent core dumps and ptrace
    unsafe {
        libc::prctl(libc::PR_SET_DUMPABLE, 0);
    }

    let key_path = match env::var("CREDENTIALS_DIRECTORY") {
        Ok(dir) => PathBuf::from(dir).join("sync-key"),
        Err(_) => {
            eprintln!("CREDENTIALS_DIRECTORY not set");
            std::process::exit(1);
        }
    };

    let key: Zeroizing<Vec<u8>> = match fs::read(&key_path) {
        Ok(k) => Zeroizing::new(k),
        Err(e) => {
            eprintln!("Failed to read {}: {}", key_path.display(), e);
            std::process::exit(1);
        }
    };

    // Lock key memory to prevent swapping to disk
    unsafe {
        libc::mlock(key.as_ptr() as *const libc::c_void, key.len());
    }

    let install_dir = match env::current_exe().and_then(|p| {
        p.parent()
            .map(|d| d.to_path_buf())
            .ok_or_else(|| std::io::Error::new(std::io::ErrorKind::Other, "no parent"))
    }) {
        Ok(d) => d,
        Err(e) => {
            eprintln!("Cannot resolve install dir: {}", e);
            std::process::exit(1);
        }
    };
    let expected_firefox = install_dir.join("firefox");

    let sock_path = env::args()
        .nth(1)
        .unwrap_or_else(|| "/run/firefox-credential-server/sock".to_string());

    // Remove stale socket
    let _ = fs::remove_file(&sock_path);

    let listener = match UnixListener::bind(&sock_path) {
        Ok(l) => l,
        Err(e) => {
            eprintln!("Failed to bind {}: {}", sock_path, e);
            std::process::exit(1);
        }
    };

    let _ = fs::set_permissions(
        &sock_path,
        fs::Permissions::from_mode(0o666),
    );

    eprintln!(
        "firefox-credential-server: listening on {}, expecting caller {}",
        sock_path,
        expected_firefox.display()
    );

    // Rate limiting: track last connection time per source UID
    let mut last_conn: HashMap<u32, Instant> = HashMap::new();
    let rate_limit = Duration::from_millis(100);

    for conn in listener.incoming() {
        match conn {
            Ok(mut stream) => {
                // Set write timeout to prevent hanging on slow/malicious clients
                let _ = stream.set_write_timeout(Some(Duration::from_secs(5)));

                let cred = match peer_cred(&stream) {
                    Ok(c) => c,
                    Err(e) => {
                        eprintln!("SO_PEERCRED failed: {}", e);
                        continue;
                    }
                };

                let pid = cred.pid as u32;
                let uid = cred.uid;

                // Rate limit by source UID
                let now = Instant::now();
                if let Some(last) = last_conn.get(&uid) {
                    if now.duration_since(*last) < rate_limit {
                        eprintln!("Rate limited uid {}", uid);
                        continue;
                    }
                }
                last_conn.insert(uid, now);

                let exe = match peer_exe(pid) {
                    Ok(p) => p,
                    Err(e) => {
                        eprintln!("readlink /proc/{}/exe failed: {}", pid, e);
                        continue;
                    }
                };

                if exe != expected_firefox {
                    eprintln!(
                        "Rejected pid {} (exe {}), expected {}",
                        pid,
                        exe.display(),
                        expected_firefox.display()
                    );
                    continue;
                }

                if let Err(e) = stream.write_all(&key) {
                    eprintln!("Write to pid {} failed: {}", pid, e);
                }
                let _ = stream.shutdown(std::net::Shutdown::Both);
            }
            Err(e) => {
                eprintln!("Accept error: {}", e);
            }
        }
    }
}

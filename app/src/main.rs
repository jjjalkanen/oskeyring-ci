use std::fs;
use std::path::PathBuf;
use std::io::{Read, Write};

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

fn main() {
    #[cfg(feature = "snap")]
    {
        match run_snap_storage() {
            Ok(_) => {},
            Err(e) => {
                eprintln!("Error accessing snap storage: {}", e);
                std::process::exit(1);
            }
        }
    }

    #[cfg(not(feature = "snap"))]
    {
        println!("All good");
    }
}

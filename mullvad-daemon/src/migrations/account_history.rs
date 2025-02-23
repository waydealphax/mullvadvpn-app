use super::{Error, Result};
use mullvad_types::{account::AccountToken, wireguard::WireguardData};
use regex::Regex;
use std::path::Path;
use talpid_types::ErrorExt;
use tokio::{
    fs,
    io::{self, AsyncReadExt, AsyncSeekExt, AsyncWriteExt},
};


const ACCOUNT_HISTORY_FILE: &str = "account-history.json";

lazy_static::lazy_static! {
    static ref ACCOUNT_REGEX: Regex = Regex::new(r"^[0-9]+$").unwrap();
}


pub async fn migrate_location(old_dir: &Path, new_dir: &Path) {
    let old_path = old_dir.join(ACCOUNT_HISTORY_FILE);
    let new_path = new_dir.join(ACCOUNT_HISTORY_FILE);
    if !old_path.exists() || new_path.exists() || new_path == old_path {
        return;
    }

    if let Err(error) = fs::copy(&old_path, &new_path).await {
        log::error!(
            "{}",
            error.display_chain_with_msg("Failed to migrate account history file location")
        );
    } else {
        let _ = fs::remove_file(old_path).await;
    }
}

pub async fn migrate_formats(settings_dir: &Path, settings: &mut serde_json::Value) -> Result<()> {
    let path = settings_dir.join(ACCOUNT_HISTORY_FILE);
    if !path.is_file() {
        return Ok(());
    }

    let mut options = fs::OpenOptions::new();
    #[cfg(unix)]
    {
        options.mode(0o600);
    }
    let mut file = options
        .write(true)
        .read(true)
        .open(path)
        .await
        .map_err(Error::ReadHistoryError)?;

    let mut bytes = vec![];
    file.read_to_end(&mut bytes)
        .await
        .map_err(Error::ReadHistoryError)?;

    if is_format_v3(&bytes) {
        return Ok(());
    }

    let token = migrate_formats_inner(&bytes, settings)?;

    file.set_len(0).await.map_err(Error::WriteHistoryError)?;
    file.seek(io::SeekFrom::Start(0))
        .await
        .map_err(Error::WriteHistoryError)?;
    file.write_all(token.as_bytes())
        .await
        .map_err(Error::WriteHistoryError)?;
    file.flush().await.map_err(Error::WriteHistoryError)?;
    file.sync_all().await.map_err(Error::WriteHistoryError)?;

    Ok(())
}

fn migrate_formats_inner(
    account_bytes: &[u8],
    settings: &mut serde_json::Value,
) -> Result<AccountToken> {
    if let Some((token, wg_data)) = try_format_v2(account_bytes) {
        settings["wireguard"] = serde_json::json!(wg_data);
        Ok(token)
    } else if let Some(token) = try_format_v1(account_bytes) {
        Ok(token)
    } else {
        Err(Error::ParseHistoryError)
    }
}

fn is_format_v3(bytes: &[u8]) -> bool {
    match std::str::from_utf8(bytes) {
        Ok(token) => token.is_empty() || ACCOUNT_REGEX.is_match(token),
        Err(_) => false,
    }
}

fn try_format_v2(bytes: &[u8]) -> Option<(AccountToken, Option<WireguardData>)> {
    #[derive(Serialize, Deserialize, Clone, Debug)]
    pub struct AccountEntry {
        pub account: AccountToken,
        pub wireguard: Option<WireguardData>,
    }
    serde_json::from_slice(bytes)
        .map(|entries: Vec<AccountEntry>| {
            entries
                .first()
                .map(|entry| (entry.account.clone(), entry.wireguard.clone()))
        })
        .unwrap_or(None)
}

fn try_format_v1(bytes: &[u8]) -> Option<AccountToken> {
    #[derive(Deserialize)]
    struct OldFormat {
        accounts: Vec<AccountToken>,
    }
    serde_json::from_slice(bytes)
        .map(|old_format: OldFormat| old_format.accounts.first().cloned())
        .unwrap_or(None)
}

#[cfg(test)]
mod test {
    use serde_json;

    pub const ACCOUNT_HISTORY_V1: &str = r#"
{
  "accounts": ["1234", "4567"]
}
"#;
    pub const ACCOUNT_HISTORY_V2: &str = r#"
[
  {
  "account": "1234",
    "wireguard": {
      "private_key": "mAdSb4AfQOsAD5O/5+zG1oIhk3cUl0jUsyOeaOMFu3o=",
      "addresses": {
        "ipv4_address": "109.111.108.101/32",
        "ipv6_address": "ffff::ffff/128"
      },
      "created": "1970-01-01T00:00:00Z"
    }
  },
  {
    "account": "4567",
    "wireguard": {
      "private_key": "mAdSb4AfQOsAD5O/5+zG1oIhk3cUl0jUsyOeaOMFu3o=",
      "addresses": {
        "ipv4_address": "109.111.108.101/32",
        "ipv6_address": "ffff::ffff/128"
      },
      "created": "1970-01-01T00:00:00Z"
    }
  }
]"#;
    pub const ACCOUNT_HISTORY_V3: &str = r#"123456"#;

    pub const OLD_SETTINGS: &str = r#"
{
  "account_token": "1234",
  "relay_settings": {
    "normal": {
      "location": {
        "only": {
          "country": "se"
        }
      },
      "tunnel_protocol": "any",
      "wireguard_constraints": {
        "port": {
          "only": {
            "protocol": "tcp",
            "port": {
              "only": 80
            }
          }
        }
      },
      "openvpn_constraints": {
        "port": {
          "only": {
            "protocol": "udp",
            "port": {
              "only": 1195
            }
          }
        }
      }
    }
  },
  "bridge_settings": {
    "normal": {
      "location": "any"
    }
  },
  "bridge_state": "auto",
  "allow_lan": true,
  "block_when_disconnected": false,
  "auto_connect": false,
  "tunnel_options": {
    "openvpn": {
      "mssfix": null
    },
    "wireguard": {
      "mtu": null,
      "rotation_interval": {
          "secs": 86400,
          "nanos": 0
      }
    },
    "generic": {
      "enable_ipv6": false
    },
    "dns_options": {
      "state": "default",
      "default_options": {
        "block_ads": false,
        "block_trackers": false
      },
      "custom_options": {
        "addresses": [
          "1.1.1.1",
          "1.2.3.4"
        ]
      }
    }
  },
  "settings_version": 5
}
"#;

    pub const NEW_SETTINGS: &str = r#"
{
  "account_token": "1234",
  "wireguard": {
    "private_key": "mAdSb4AfQOsAD5O/5+zG1oIhk3cUl0jUsyOeaOMFu3o=",
    "addresses": {
      "ipv4_address": "109.111.108.101/32",
      "ipv6_address": "ffff::ffff/128"
    },
    "created": "1970-01-01T00:00:00Z"
  },
  "relay_settings": {
    "normal": {
      "location": {
        "only": {
          "country": "se"
        }
      },
      "tunnel_protocol": "any",
      "wireguard_constraints": {
        "port": {
          "only": {
            "protocol": "tcp",
            "port": {
              "only": 80
            }
          }
        }
      },
      "openvpn_constraints": {
        "port": {
          "only": {
            "protocol": "udp",
            "port": {
              "only": 1195
            }
          }
        }
      }
    }
  },
  "bridge_settings": {
    "normal": {
      "location": "any"
    }
  },
  "bridge_state": "auto",
  "allow_lan": true,
  "block_when_disconnected": false,
  "auto_connect": false,
  "tunnel_options": {
    "openvpn": {
      "mssfix": null
    },
    "wireguard": {
      "mtu": null,
      "rotation_interval": {
          "secs": 86400,
          "nanos": 0
      }
    },
    "generic": {
      "enable_ipv6": false
    },
    "dns_options": {
      "state": "default",
      "default_options": {
        "block_ads": false,
        "block_trackers": false
      },
      "custom_options": {
        "addresses": [
          "1.1.1.1",
          "1.2.3.4"
        ]
      }
    }
  },
  "settings_version": 5
}
"#;


    // Test whether the current format is parsed correctly
    #[test]
    fn test_v3() {
        assert!(!super::is_format_v3(ACCOUNT_HISTORY_V1.as_bytes()));
        assert!(!super::is_format_v3(ACCOUNT_HISTORY_V2.as_bytes()));
        assert!(super::is_format_v3(ACCOUNT_HISTORY_V3.as_bytes()));
    }

    #[test]
    fn test_v2() {
        assert!(super::try_format_v2(ACCOUNT_HISTORY_V1.as_bytes()).is_none());

        let mut old_settings = serde_json::from_str(OLD_SETTINGS).unwrap();
        let new_settings: serde_json::Value = serde_json::from_str(NEW_SETTINGS).unwrap();

        // Test whether the wireguard data is moved to the settings correctly
        let token =
            super::migrate_formats_inner(ACCOUNT_HISTORY_V2.as_bytes(), &mut old_settings).unwrap();

        assert_eq!(&old_settings, &new_settings);
        assert_eq!(token, "1234");
    }

    #[test]
    fn test_v1() {
        let token = super::try_format_v1(ACCOUNT_HISTORY_V1.as_bytes());
        assert_eq!(token, Some("1234".to_string()));
    }
}

use std::{
    ffi::{self, CString},
    fs, io,
    path::Path,
};

const PROC_SYS_NET_IPV4_CONF_SRC_VLAID_MARK: &'static str =
    "/proc/sys/net/ipv4/conf/all/src_valid_mark";
const PROC_SYS_NET_IPV6_CONF_SRC_VLAID_MARK: &'static str =
    "/proc/sys/net/ipv6/conf/all/src_valid_mark";

/// Converts an interface name into the corresponding index.
pub fn iface_index(name: &str) -> Result<libc::c_uint, IfaceIndexLookupError> {
    let c_name = CString::new(name)
        .map_err(|e| IfaceIndexLookupError::InvalidInterfaceName(name.to_owned(), e))?;
    let index = unsafe { libc::if_nametoindex(c_name.as_ptr()) };
    if index == 0 {
        Err(IfaceIndexLookupError::InterfaceLookupError(
            name.to_owned(),
            io::Error::last_os_error(),
        ))
    } else {
        Ok(index)
    }
}

#[derive(Debug, err_derive::Error)]
pub enum IfaceIndexLookupError {
    #[error(display = "Invalid network interface name: {}", _0)]
    InvalidInterfaceName(String, #[error(source)] ffi::NulError),
    #[error(display = "Failed to get index for interface {}", _0)]
    InterfaceLookupError(String, #[error(source)] io::Error),
}

// b"mole" is [ 0x6d, 0x6f 0x6c, 0x65 ]
pub const TUNNEL_FW_MARK: u32 = 0x6d6f6c65;
pub const TUNNEL_TABLE_ID: u32 = 0x6d6f6c65;

pub fn set_src_valid_mark_sysctl() -> io::Result<(Option<Vec<u8>>, Option<Vec<u8>>)> {
    let ipv4_setting = set_src_valid_mark_for_ipv(PROC_SYS_NET_IPV4_CONF_SRC_VLAID_MARK.as_ref())?;
    let ipv6_setting =
        set_src_valid_mark_for_ipv(PROC_SYS_NET_IPV6_CONF_SRC_VLAID_MARK.as_ref()).unwrap_or(None);
    Ok((ipv4_setting, ipv6_setting))
}

pub fn reset_src_valid_mark_syscetl(ipv4: Option<Vec<u8>>, ipv6: Option<Vec<u8>>) {
    let remove_fn = |path, value, error_msg| {
        if let Some(old_value) = value {
            if let Err(err) = reset_src_valid_mark_for_ipv(path, old_value) {
                log::error!(
                    "Failed to reset 'src_valid_mark' for {}: {}",
                    error_msg,
                    err
                );
            }
        }
    };

    remove_fn(PROC_SYS_NET_IPV4_CONF_SRC_VLAID_MARK.as_ref(), ipv4, "IPv4");
    remove_fn(PROC_SYS_NET_IPV6_CONF_SRC_VLAID_MARK.as_ref(), ipv6, "IPv6");
}


fn set_src_valid_mark_for_ipv(src_valid_mark_path: &Path) -> io::Result<Option<Vec<u8>>> {
    let current_value = fs::read(src_valid_mark_path)?;
    if current_value == b"1" {
        Ok(None)
    } else {
        log::error!("Setting {} to 1", src_valid_mark_path.display());
        fs::write(src_valid_mark_path, b"1")?;
        Ok(Some(current_value))
    }
}

fn reset_src_valid_mark_for_ipv(src_valid_mark_path: &Path, value: Vec<u8>) -> io::Result<()> {
    fs::write(src_valid_mark_path, value)
}

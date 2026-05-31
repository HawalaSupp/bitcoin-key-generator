use rust_app::ffi::{
    hawala_derive_address_from_key, hawala_estimate_fees, hawala_free_string,
    hawala_restore_wallet, hawala_validate_address, hawala_validate_mnemonic,
};
use serde_json::Value;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

unsafe fn take_json(ptr: *mut c_char) -> Value {
    assert!(!ptr.is_null(), "FFI returned a null response pointer");
    let json = CStr::from_ptr(ptr)
        .to_str()
        .expect("FFI response should be valid UTF-8")
        .to_owned();
    hawala_free_string(ptr);
    serde_json::from_str(&json).expect("FFI response should be JSON")
}

fn call_with_malformed_json(f: extern "C" fn(*const c_char) -> *mut c_char) -> Value {
    let input = CString::new("{not-json").expect("test input has no interior null");
    unsafe { take_json(f(input.as_ptr())) }
}

fn call_with_null(f: extern "C" fn(*const c_char) -> *mut c_char) -> Value {
    unsafe { take_json(f(std::ptr::null())) }
}

#[test]
fn launch_scope_ffi_rejects_null_input() {
    for f in [
        hawala_restore_wallet,
        hawala_validate_mnemonic,
        hawala_derive_address_from_key,
        hawala_estimate_fees,
        hawala_validate_address,
    ] {
        let response = call_with_null(f);
        assert_eq!(response["success"], false);
        assert!(response["error"]["message"].as_str().is_some());
    }
}

#[test]
fn launch_scope_ffi_rejects_malformed_json() {
    for f in [
        hawala_restore_wallet,
        hawala_validate_mnemonic,
        hawala_derive_address_from_key,
        hawala_estimate_fees,
        hawala_validate_address,
    ] {
        let response = call_with_malformed_json(f);
        assert_eq!(response["success"], false);
        assert!(response["error"]["message"].as_str().is_some());
    }
}

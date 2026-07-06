fn main() {
    // Raw link args emitted by whisperkit-swift-rs do not propagate transitively to
    // this Tauri binary. Repeat the Swift concurrency runtime rpath here.
    #[cfg(target_os = "macos")]
    println!("cargo:rustc-link-arg=-Wl,-rpath,/usr/lib/swift");

    tauri_build::build()
}

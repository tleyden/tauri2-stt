use swift_rs::SwiftLinker;

fn main() {
    SwiftLinker::new("14.0")
        .with_package("whisperkit-swift", "./whisperkit-swift/")
        .link();

    println!("cargo:rustc-link-arg=-Wl,-rpath,/usr/lib/swift");
}

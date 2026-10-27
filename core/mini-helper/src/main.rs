use cef::{args::Args, library_loader::LibraryLoader, sandbox::Sandbox, *};

fn main() {
    let arguments = Args::new();

    let mut sandbox = Sandbox::new();
    sandbox.initialize(arguments.as_main_args());

    let executable = std::env::current_exe().expect("cannot resolve the helper executable path");
    let loader = LibraryLoader::new(&executable, true);
    assert!(loader.load(), "cannot load the Chromium Embedded Framework");

    let _ = api_hash(sys::CEF_API_VERSION_LAST, 0);

    let exit_code = execute_process(
        Some(arguments.as_main_args()),
        None::<&mut App>,
        std::ptr::null_mut(),
    );
    drop(loader);
    drop(sandbox);
    std::process::exit(exit_code);
}

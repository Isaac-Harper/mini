use cef::{args::Args, library_loader::LibraryLoader, sandbox::Sandbox, *};

wrap_app! {
    struct HelperApp;

    impl App {
        fn render_process_handler(&self) -> Option<RenderProcessHandler> {
            Some(HelperRenderProcessHandler::new())
        }
    }
}

wrap_render_process_handler! {
    struct HelperRenderProcessHandler;

    impl RenderProcessHandler {
        fn on_context_created(
            &self,
            _browser: Option<&mut Browser>,
            frame: Option<&mut Frame>,
            context: Option<&mut V8Context>,
        ) {
            let (Some(frame), Some(context)) = (frame, context) else {
                return;
            };
            if frame.is_main() != 1 {
                return;
            }
            let script = early_errors::script();
            let mut result = None;
            let mut exception = None;
            context.eval(
                Some(&CefString::from(script.as_str())),
                None,
                0,
                Some(&mut result),
                Some(&mut exception),
            );
        }
    }
}

fn main() {
    let arguments = Args::new();

    let mut sandbox = Sandbox::new();
    sandbox.initialize(arguments.as_main_args());

    let executable = std::env::current_exe().expect("cannot resolve the helper executable path");
    let loader = LibraryLoader::new(&executable, true);
    assert!(loader.load(), "cannot load the Chromium Embedded Framework");

    let _ = api_hash(sys::CEF_API_VERSION_LAST, 0);

    let mut application = HelperApp::new();
    let exit_code = execute_process(
        Some(arguments.as_main_args()),
        Some(&mut application),
        std::ptr::null_mut(),
    );
    drop(loader);
    drop(sandbox);
    std::process::exit(exit_code);
}

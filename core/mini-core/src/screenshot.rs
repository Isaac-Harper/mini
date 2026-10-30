use base64::Engine as _;
use cef::*;
use serde::Deserialize;
use std::{cell::RefCell, collections::HashMap};

use crate::{
    MiniTabId,
    state::{callbacks, next_request_id, tab_is_live, with_tab},
};

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum CaptureFormat {
    Jpeg,
    Png,
}

impl CaptureFormat {
    pub fn from_raw(raw: i32) -> Self {
        match raw {
            0 => Self::Jpeg,
            1 => Self::Png,
            other => panic!("unknown capture format {other}"),
        }
    }
}

#[repr(C)]
#[derive(Deserialize, Debug, PartialEq, Clone, Copy)]
pub struct MiniElementBox {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
    #[serde(rename = "ratio")]
    pub pixel_ratio: f64,
}

#[derive(Deserialize)]
struct EvaluateResult {
    result: EvaluateValue,
}

#[derive(Deserialize)]
struct EvaluateValue {
    value: Option<MiniElementBox>,
}

#[derive(Deserialize)]
struct CaptureResult {
    data: String,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Stage {
    HidingScrollbars,
    Measuring,
    Capturing,
}

struct Pipeline {
    tab: MiniTabId,
    request: u64,
    host: BrowserHost,
    format: CaptureFormat,
    element_point: Option<(f64, f64)>,
    element: Option<MiniElementBox>,
    stage: Stage,
}

thread_local! {
    static PIPELINES: RefCell<HashMap<i32, Pipeline>> = RefCell::new(HashMap::new());
}

wrap_dev_tools_message_observer! {
    struct SnapshotObserver {}

    impl DevToolsMessageObserver {
        fn on_dev_tools_method_result(
            &self,
            _browser: Option<&mut Browser>,
            message_id: ::std::os::raw::c_int,
            success: ::std::os::raw::c_int,
            result: Option<&[u8]>,
        ) {
            let Some(mut pipeline) = PIPELINES.with_borrow_mut(|pipelines| pipelines.remove(&message_id)) else {
                return;
            };
            if !tab_is_live(pipeline.tab) {
                return;
            }
            let succeeded = success != 0;
            match pipeline.stage {
                Stage::HidingScrollbars if pipeline.element_point.is_some() => send_measure(pipeline),
                Stage::HidingScrollbars => send_capture(pipeline),
                Stage::Measuring => {
                    pipeline.element = if succeeded { result.and_then(parse_element_box) } else { None };
                    send_capture(pipeline);
                }
                Stage::Capturing => {
                    let image = if succeeded { result.and_then(|result| parse_image(result, pipeline.format)) } else { None };
                    finish(&pipeline, image.unwrap_or_default());
                }
            }
        }
    }
}

fn message_id() -> i32 {
    i32::try_from(next_request_id() % i32::MAX as u64).expect("message id fits i32")
}

fn execute(host: &BrowserHost, message_id: i32, method: &str, params: &mut DictionaryValue) {
    let sent =
        host.execute_dev_tools_method(message_id, Some(&CefString::from(method)), Some(params));
    assert_eq!(sent, message_id, "{method} was not sent");
}

fn dictionary() -> DictionaryValue {
    dictionary_value_create().expect("cannot create a dictionary value")
}

fn await_result(mut pipeline: Pipeline, stage: Stage) -> (BrowserHost, i32) {
    let message_id = message_id();
    let host = pipeline.host.clone();
    pipeline.stage = stage;
    PIPELINES.with_borrow_mut(|pipelines| pipelines.insert(message_id, pipeline));
    (host, message_id)
}

fn set_scrollbars_hidden(host: &BrowserHost, message_id: i32, hidden: bool) {
    let mut params = dictionary();
    params.set_bool(Some(&CefString::from("hidden")), hidden.into());
    execute(
        host,
        message_id,
        "Emulation.setScrollbarsHidden",
        &mut params,
    );
}

pub fn measure_expression(x: f64, y: f64) -> String {
    format!(
        "(function(){{var element=document.elementFromPoint({x},{y});if(!element)return null;var rect=element.getBoundingClientRect();\
return {{x:rect.left,y:rect.top,width:rect.width,height:rect.height,ratio:window.devicePixelRatio}};}})()"
    )
}

fn send_measure(pipeline: Pipeline) {
    let (x, y) = pipeline.element_point.expect("measure without a point");
    let (host, message_id) = await_result(pipeline, Stage::Measuring);
    let mut params = dictionary();
    params.set_string(
        Some(&CefString::from("expression")),
        Some(&CefString::from(measure_expression(x, y).as_str())),
    );
    params.set_bool(Some(&CefString::from("returnByValue")), 1);
    execute(&host, message_id, "Runtime.evaluate", &mut params);
}

fn send_capture(pipeline: Pipeline) {
    let format = pipeline.format;
    let (host, message_id) = await_result(pipeline, Stage::Capturing);
    let mut params = dictionary();
    match format {
        CaptureFormat::Jpeg => {
            params.set_string(
                Some(&CefString::from("format")),
                Some(&CefString::from("jpeg")),
            );
            params.set_int(Some(&CefString::from("quality")), 90);
            params.set_bool(Some(&CefString::from("optimizeForSpeed")), 1);
        }
        CaptureFormat::Png => {
            params.set_string(
                Some(&CefString::from("format")),
                Some(&CefString::from("png")),
            );
            params.set_bool(Some(&CefString::from("captureBeyondViewport")), 0);
            params.set_bool(Some(&CefString::from("fromSurface")), 1);
        }
    }
    execute(&host, message_id, "Page.captureScreenshot", &mut params);
}

fn finish(pipeline: &Pipeline, image: Vec<u8>) {
    if pipeline.format == CaptureFormat::Png {
        set_scrollbars_hidden(&pipeline.host, message_id(), false);
    }
    let element_pointer = pipeline
        .element
        .as_ref()
        .map_or(std::ptr::null(), std::ptr::from_ref);
    unsafe {
        (callbacks().page_snapshot_received)(
            pipeline.tab,
            pipeline.request,
            image.as_ptr(),
            image.len(),
            element_pointer,
        )
    };
}

pub fn parse_element_box(result: &[u8]) -> Option<MiniElementBox> {
    let element = serde_json::from_slice::<EvaluateResult>(result)
        .ok()?
        .result
        .value?;
    let values = [
        element.x,
        element.y,
        element.width,
        element.height,
        element.pixel_ratio,
    ];
    let sane = values
        .iter()
        .all(|value| value.is_finite() && value.abs() < 10_000_000.0)
        && element.width > 0.0
        && element.height > 0.0
        && element.pixel_ratio > 0.0;
    sane.then_some(element)
}

pub fn parse_image(result: &[u8], format: CaptureFormat) -> Option<Vec<u8>> {
    let capture = serde_json::from_slice::<CaptureResult>(result).ok()?;
    let image = base64::engine::general_purpose::STANDARD
        .decode(capture.data)
        .ok()?;
    let signature: &[u8] = match format {
        CaptureFormat::Jpeg => b"\xff\xd8",
        CaptureFormat::Png => b"\x89PNG",
    };
    image.starts_with(signature).then_some(image)
}

pub fn capture(
    tab: MiniTabId,
    browser: &Browser,
    request: u64,
    format: CaptureFormat,
    element_point: Option<(f64, f64)>,
) {
    let host = browser.host().expect("browser has no host");
    if with_tab(tab, |state| state.snapshot_observer.is_none()) {
        let mut observer = SnapshotObserver::new();
        let registration = host
            .add_dev_tools_message_observer(Some(&mut observer))
            .expect("CEF refused the devtools observer");
        with_tab(tab, |state| state.snapshot_observer = Some(registration));
    }
    let pipeline = Pipeline {
        tab,
        request,
        host,
        format,
        element_point,
        element: None,
        stage: Stage::HidingScrollbars,
    };
    match format {
        CaptureFormat::Jpeg => send_capture(pipeline),
        CaptureFormat::Png => {
            let (host, message_id) = await_result(pipeline, Stage::HidingScrollbars);
            set_scrollbars_hidden(&host, message_id, true);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{
        CaptureFormat, MiniElementBox, measure_expression, parse_element_box, parse_image,
    };

    #[test]
    fn reads_the_measured_box() {
        let result = br#"{"result":{"type":"object","value":{"x":10.5,"y":-20,"width":300,"height":40,"ratio":3}}}"#;
        assert_eq!(
            parse_element_box(result),
            Some(MiniElementBox {
                x: 10.5,
                y: -20.0,
                width: 300.0,
                height: 40.0,
                pixel_ratio: 3.0
            })
        );
    }

    #[test]
    fn rejects_missing_or_empty_boxes() {
        assert_eq!(
            parse_element_box(br#"{"result":{"type":"object","subtype":"null","value":null}}"#),
            None
        );
        assert_eq!(parse_element_box(br#"{"result":{"type":"object","value":{"x":0,"y":0,"width":0,"height":4,"ratio":2}}}"#), None);
        assert_eq!(parse_element_box(b"nonsense"), None);
    }

    #[test]
    fn decodes_only_the_requested_format() {
        assert_eq!(
            parse_image(br#"{"data":"iVBORw0KGgo="}"#, CaptureFormat::Png),
            Some(b"\x89PNG\r\n\x1a\n".to_vec())
        );
        assert_eq!(
            parse_image(br#"{"data":"/9j/"}"#, CaptureFormat::Jpeg),
            Some(vec![0xff, 0xd8, 0xff])
        );
        assert_eq!(parse_image(br#"{"data":"/9j/"}"#, CaptureFormat::Png), None);
        assert_eq!(
            parse_image(br#"{"data":"aGVsbG8="}"#, CaptureFormat::Png),
            None
        );
        assert_eq!(parse_image(br#"{"data":"%%%"}"#, CaptureFormat::Jpeg), None);
        assert_eq!(parse_image(b"not json", CaptureFormat::Jpeg), None);
    }

    #[test]
    fn formats_follow_the_header_values() {
        assert_eq!(CaptureFormat::from_raw(0), CaptureFormat::Jpeg);
        assert_eq!(CaptureFormat::from_raw(1), CaptureFormat::Png);
    }

    #[test]
    fn measures_at_the_given_point() {
        assert!(measure_expression(12.5, 40.0).contains("document.elementFromPoint(12.5,40)"));
    }
}

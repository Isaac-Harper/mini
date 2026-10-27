use cef::*;

use crate::{
    MiniTabId,
    state::{callbacks, with_core},
};

const MAXIMUM_IMAGE_SIZE: u32 = 64;
const SCALE_FACTOR: f32 = 2.0;

fn report(tab: MiniTabId, png: &[u8]) {
    let pointer = if png.is_empty() {
        std::ptr::null()
    } else {
        png.as_ptr()
    };
    unsafe { (callbacks().favicon_changed)(tab, pointer, png.len()) };
}

fn next_generation(tab: MiniTabId) -> u64 {
    with_core(|core| {
        let state = core
            .tabs
            .get_mut(&tab)
            .unwrap_or_else(|| panic!("favicon change for unregistered tab {tab}"));
        state.favicon_generation += 1;
        state.favicon_generation
    })
}

fn is_current(tab: MiniTabId, generation: u64) -> bool {
    with_core(|core| {
        core.tabs
            .get(&tab)
            .is_some_and(|state| state.favicon_generation == generation)
    })
}

pub fn favicon_urls_changed(tab: MiniTabId, browser: &Browser, first_url: Option<String>) {
    let generation = next_generation(tab);
    let Some(first_url) = first_url else {
        report(tab, &[]);
        return;
    };
    let mut callback = FaviconDownload::new(tab, generation);
    browser.host().expect("browser has no host").download_image(
        Some(&CefString::from(first_url.as_str())),
        1,
        MAXIMUM_IMAGE_SIZE,
        0,
        Some(&mut callback),
    );
}

fn png_bytes(image: &Image) -> Vec<u8> {
    let mut pixel_width = 0;
    let mut pixel_height = 0;
    let Some(png) = image.as_png(
        SCALE_FACTOR,
        1,
        Some(&mut pixel_width),
        Some(&mut pixel_height),
    ) else {
        return Vec::new();
    };
    let length = png.size();
    let data = png.raw_data();
    if length == 0 || data.is_null() {
        return Vec::new();
    }
    unsafe { std::slice::from_raw_parts(data.cast::<u8>(), length) }.to_vec()
}

wrap_download_image_callback! {
    struct FaviconDownload {
        tab: MiniTabId,
        generation: u64,
    }

    impl DownloadImageCallback {
        fn on_download_image_finished(
            &self,
            _image_url: Option<&CefString>,
            _http_status_code: ::std::os::raw::c_int,
            image: Option<&mut Image>,
        ) {
            if !is_current(self.tab, self.generation) {
                return;
            }
            let png = image
                .filter(|image| image.is_empty() == 0)
                .map(|image| png_bytes(image))
                .unwrap_or_default();
            report(self.tab, &png);
        }
    }
}

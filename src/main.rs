use std::collections::HashMap;

use sfml::window::*;
use sfml::graphics::*;

mod vn;
mod scene_parser;

use crate::vn::buttons::*;
use crate::vn::*;

fn main() {
    let mut window = RenderWindow::new(
        (1280, 1024),
        "Vacances",
        Style::CLOSE,
        &Default::default()
    );
    window.set_framerate_limit(60);

    let scenes = scene_parser::parse_scene_file();
    let mut scene = &scenes["start"];

    loop {
        let mut changed_scene = None;
        let button_rects = buttons_to_rects(
            &window,
            &scene.answers
        );

        while let Some(event) = window.poll_event() {
            if let Some(bes) = button_events(&event, &button_rects, &scene.answers) {
                for be in bes  {
                    match be {
                        SceneAction::ChangeScene(new_scene) => changed_scene = Some(&scenes[new_scene]),
                    }
                }
            }

            match event {
                Event::Closed => return,
                _ => ()
            }
        }

        window.clear(&Color::WHITE);

        vn::draw_text_frame(&mut window, &scene);
        draw_buttons(
            &mut window,
            &button_rects,
            &scene.answers
        );

        if changed_scene.is_some() { scene = changed_scene.unwrap(); }

        window.display();
    }
}

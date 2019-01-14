use sfml::window::*;
use sfml::graphics::*;

use font_loader::system_fonts;

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

    let prop = system_fonts::FontPropertyBuilder::new().family("Ubuntu").build();
    let (font_data, _) = system_fonts::get(&prop).unwrap();
    let font = Font::from_memory(&font_data).unwrap();
    let font = &font;

    loop {
        let mut changed_scene = None;
        let renderable_answers = to_renderable_answers(
            &window,
            &scene.answers,
            &font
        );

        while let Some(event) = window.poll_event() {
            if let Some(bes) = handle_answer_events(&event, &renderable_answers) {
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
        draw_answers(
            &mut window,
            &renderable_answers
        );

        if changed_scene.is_some() { scene = changed_scene.unwrap(); }

        window.display();
    }
}

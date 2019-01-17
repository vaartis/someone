use sfml::window::*;
use sfml::system::*;
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

    let mut scenes = scene_parser::parse_scene_file(include_str!("../scenes/chapter_1.yml"));
    scenes.extend(scene_parser::parse_scene_file(include_str!("../scenes/chapter_2.yml")));
    scenes.extend(scene_parser::parse_scene_file(include_str!("../scenes/chapter_3.yml")));
    let mut scene = &scenes["start"];

    let prop = system_fonts::FontPropertyBuilder::new().family("Ubuntu").build();
    let (font_data, _) = system_fonts::get(&prop).unwrap();
    let font = Font::from_memory(&font_data).unwrap();

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
                Event::Resized { width, height } => {
                    // Resize the view to the new size and set the center in the center of the width & height,
                    // so nothing seems to change compared to the default view
                    window.set_view(
                        &View::new(
                            Vector2f::new((width / 2) as f32, (height / 2) as f32),
                            Vector2f::new(width as f32, height as f32)
                        )
                    );
                },
                _ => ()
            }
        }

        window.clear(&Color::WHITE);

        vn::draw_text_frame(&mut window, &scene, &font);
        draw_answers(
            &mut window,
            &renderable_answers
        );

        if changed_scene.is_some() { scene = changed_scene.unwrap(); }

        window.display();
    }
}

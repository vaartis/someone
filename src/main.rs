use std::collections::HashMap;

use sfml::window::*;
use sfml::graphics::*;

mod vn;

use crate::vn::buttons::*;

fn main() {
    let mut window = RenderWindow::new(
        (1280, 1024),
        "Vacances",
        Style::CLOSE,
        &Default::default()
    );
    window.set_framerate_limit(60);

    let mut scenes = HashMap::<String, vn::Scene>::new();
    scenes.insert(
        "Scene1".to_string(),
        vn::Scene {
            text: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. In nibh mi, pharetra sed tempus id, posuere eu magna. In rutrum justo ut augue accumsan porttitor. In ex ipsum, condimentum quis porta vel, facilisis lobortis nunc. Quisque eleifend condimentum tellus, vitae ornare nibh auctor vel.".to_string(),
            answers: vec![
                Button { text: "Change to scene 2".to_string(), action: ButtonAction::ChangeScene("Scene2".to_string()) }
            ]
        }
    );
    scenes.insert(
        "Scene2".to_string(),
        vn::Scene {
            text: "Lorem ipsum dolor sit amet, consectetur adipiscing elit.".to_string(),
            answers: vec![
                Button { text: "Change to scene 1".to_string(), action: ButtonAction::ChangeScene("Scene1".to_string()) }
            ]
        }
    );

    let mut scene = &scenes["Scene1"];

    loop {
        let button_rects = buttons_to_rects(
            &window,
            &scene.answers
        );

        while let Some(event) = window.poll_event() {
            match button_events(&event, &button_rects, &scene.answers) {
                Some(ButtonAction::ChangeScene(new_scene)) =>
                    scene = &scenes[new_scene],
                None => {}
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

        window.display();
    }
}

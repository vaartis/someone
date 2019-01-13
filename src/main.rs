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
    loop {
        let buttons = vec![
            Button { text: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. In nibh mi, pharetra sed tempus id, posuere eu magna. In rutrum justo ut augue accumsan porttitor. In ex ipsum, condimentum quis porta vel, facilisis lobortis nunc. Quisque eleifend condimentum tellus, vitae ornare nibh auctor vel.".to_string() },
            Button { text: "Test2".to_string() },
            Button { text: "Test3".to_string() },
            Button { text: "Test4".to_string() },
            Button { text: "Test5".to_string() },
            Button { text: "Test6".to_string() }
        ];
        let button_rects = buttons_to_rects(
            &window,
            &buttons
        );

        while let Some(event) = window.poll_event() {
            button_events(&event, &button_rects, &buttons);

            match event {
                Event::Closed => return,
                _ => ()
            }
        }

        window.clear(&Color::WHITE);

        vn::draw_text_frame(&mut window);
        draw_buttons(
            &mut window,
            &button_rects,
            &buttons
        );

        window.display();
    }
}

use sfml::system::*;
use sfml::window::*;
use sfml::graphics::*;

use textwrap::fill;

pub struct Button {
    pub text: String,
    // action: ButtonAction
}

pub fn buttons_to_rects(window: &RenderWindow, buttons: &Vec<Button>) -> Vec<Rect<u32>> {
    let button_count = buttons.len() as u32;

    let win_size = window.size();

    // Space we have
    let starting_y = win_size.y - (win_size.y / 100 * 29);
    let ending_y = win_size.y - (win_size.y / 100 * 1);

    let starting_x = win_size.x / (100 * 1);
    let ending_x = win_size.x - (win_size.x / 100 * 1);

    /* FIXME: smarter detection of these limitations */
    let height_per_button = (ending_y - starting_y) / (if button_count > 4 { 4 } else { button_count });
    let width_per_button = (ending_x - starting_x - (win_size.x / 100 * 1)) / (if button_count > 2 { 2 } else { button_count });

    let mut rects = vec![];
    let (mut current_x, mut current_y) = (starting_x, starting_y);

    for _ in 0..buttons.len() {
        rects.push(
            Rect::new(
                current_x, current_y, width_per_button, height_per_button
            )
        );

        current_x += width_per_button + (win_size.x / 100 * 1);
        if current_x + width_per_button > ending_x  {
            current_x = starting_x;
            current_y += height_per_button + (win_size.y / 100 * 1);
        }
    }
    // panic!();

    rects
}

pub fn draw_buttons(window: &mut RenderWindow, button_rects: &Vec<Rect<u32>>, buttons: &Vec<Button>) {
    let font = Font::from_file("/usr/share/fonts/ubuntu-font-family/Ubuntu-B.ttf").unwrap(); // Use fontconfig or something

    for (i, brect) in button_rects.iter().enumerate() {
        let mut rect = RectangleShape::with_size(Vector2f::new(brect.width as f32, brect.height as f32));

        rect.set_position(Vector2f::new(brect.left as f32, brect.top as f32));
        rect.set_outline_color(&Color::BLACK);
        rect.set_outline_thickness(2.5);

        let txt = &buttons[i].text;
        let supposed_text_fit = brect.width / (16 / 2);
        let wrapped_text = fill(&txt, supposed_text_fit as usize);

        let mut text = Text::new(&wrapped_text, &font, 16);
        text.set_fill_color(&Color::BLACK);
        text.set_position(Vector2f::new(brect.left as f32, brect.top as f32));

        window.draw(&rect);
        window.draw(&text);
    }
}

pub fn button_events(event: &Event, button_rects: &Vec<Rect<u32>>, buttons: &Vec<Button>) {
    match event {
        Event::MouseButtonReleased {button: sfml::window::mouse::Button::Left , x, y } => {
            if let Some(button_index) = button_rects.iter().position(|el: &Rect<u32>| el.contains2(*x as u32, *y as u32)) {
                println!("{}", buttons[button_index].text);
            }
        },
        _ => {}
    }
}

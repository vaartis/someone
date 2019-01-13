use sfml::system::*;
use sfml::graphics::*;

pub mod buttons;

pub struct Scene {
    pub text: String,
    pub answers: Vec<buttons::Button>
}

pub fn draw_text_frame(window: &mut RenderWindow, scene: &Scene) {
    let win_size = window.size();

    let height_2p = win_size.y / 100 * 2;
    let width_2p = win_size.x / 100 * 2;

    // most of the window
    let rect_height = win_size.y / 100 * (80 - 10);
    let rect_width = win_size.x - (width_2p * 2);

    let mut rect = RectangleShape::with_size(Vector2f::new(rect_width as f32, rect_height as f32));
    rect.set_outline_thickness(2.0);
    rect.set_outline_color(&Color::BLACK);
    rect.set_fill_color(&Color::WHITE);
    rect.set_position(Vector2f::new(width_2p as f32, height_2p as f32));

    let font = Font::from_file("/usr/share/fonts/ubuntu-font-family/Ubuntu-B.ttf").unwrap(); // Use fontconfig or something

    let txt = &scene.text;
    let supposed_text_fit = rect_width / (16 / 2);
    let wrapped_text = textwrap::fill(&txt, supposed_text_fit as usize);

    let mut text = Text::new(&wrapped_text, &font, 16);
    text.set_fill_color(&Color::BLACK);
    text.set_position(Vector2f::new(width_2p as f32, height_2p  as f32));

    window.draw(&rect);
    window.draw(&text);
}

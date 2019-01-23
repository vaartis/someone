use sfml::system::*;
use sfml::graphics::*;
use sfml::window::*;

#[derive(Debug, Default)]
pub struct TerminalState {
    pub whole_text: String,
    pub line: String,
    // TODO: history
}

pub fn draw_terminal(window: &mut RenderWindow, font: &Font, state: &mut TerminalState) {
    let win_size = window.size();

    let height_offset = win_size.y / 100 * 2;
    let width_offset = win_size.x / 100 * 1;

    // most of the window
    let rect_height = win_size.y / 100 * (80 - 10);
    let rect_width = win_size.x - (width_offset * 2);

    let mut rect = RectangleShape::with_size(Vector2f::new(rect_width as f32, rect_height as f32));
    rect.set_outline_thickness(2.0);
    rect.set_outline_color(&Color::BLACK);
    rect.set_fill_color(&Color::BLACK);
    rect.set_position(Vector2f::new(width_offset as f32, height_offset as f32));

    let line_txt = format!("$ {}", &state.line);
    let txt_to_drw: String = state.whole_text.clone() + &line_txt;

    let mut text = Text::new(&txt_to_drw, &font, 16);
    text.set_fill_color(&Color::WHITE);
    text.set_position(Vector2f::new((width_offset * 2) as f32, (height_offset * 2)  as f32));

    window.draw(&rect);
    window.draw(&text);
}

pub fn handle_term_events(event: &Event, terminal_state: &mut TerminalState) {
    match event {
        Event::TextEntered { unicode: ch } => {
            match *ch {
                // Backspace
                '\u{8}' => {
                    if Key::LAlt.is_pressed() {
                        let space = terminal_state.line.rfind(' ');
                        terminal_state.line.drain(space.unwrap_or(0)..terminal_state.line.len());
                    } else {
                        terminal_state.line.pop(); ()
                    }

                },
                // Enter
                '\r' => {
                    terminal_state.whole_text += &format!("$ {} \n", terminal_state.line);
                    terminal_state.line.clear();
                    // TODO: Process the command
                }
                _ => terminal_state.line.push(*ch)
            }
        }

        _ => {}
    }
}

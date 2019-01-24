use sfml::system::*;
use sfml::graphics::*;
use sfml::window::*;

#[derive(Debug, Default)]
pub struct TerminalState {
    pub whole_text: String,
    pub line: String,
    // TODO: history
}

const FONT_SIZE: u32 = 16;

/// Calculates how many characters of the string could fit into a line of a given width.
pub fn chars_fit_into(string: &str, width: f32, font: &Font, font_size: u32) -> usize {
    // TODO: figure out what "outline thickness" is, for now 1.0 seems to do the job fine
    let current_width = string.chars().fold(0.0, |acc, ch| acc + font.glyph(ch as u32, font_size, false, 1.0).bounds.width);

    if current_width < width {
        string.len()
    } else {
        chars_fit_into(&string[..string.len() - 1], width, font, font_size)
    }
}

pub fn draw_terminal(window: &mut RenderWindow, font: &Font, state: &mut TerminalState) {
    let win_size = window.size();

    let height_offset = win_size.y / 100 * 2;
    let width_offset = win_size.x / 100 * 1;

    // most of the window
    let rect_height = win_size.y / 100 * (80 - 10);
    let rect_width = win_size.x - (width_offset * 2);
    let allowed_text_width = rect_width - (width_offset * 2);

    let mut rect = RectangleShape::with_size(Vector2f::new(rect_width as f32, rect_height as f32));
    rect.set_outline_thickness(2.0);
    rect.set_outline_color(&Color::BLACK);
    rect.set_fill_color(&Color::BLACK);
    rect.set_position(Vector2f::new(width_offset as f32, height_offset as f32));

    // Format the line so it'd include $ in the beginning
    let line = format!("$ {}", &state.line);
    let supposed_fit_length = chars_fit_into(&line, allowed_text_width as f32, &font, FONT_SIZE);

    let new_line = if line.len() > supposed_fit_length {
        let (before, after) = line.split_at(supposed_fit_length - 1);
        format!("{}\n{}", before, after)
    } else {
        line
    };

    let txt_to_use = format!("{}{}", &state.whole_text, &new_line);
    let mut text = Text::new(&txt_to_use, &font, FONT_SIZE);

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

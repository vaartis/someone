use sfml::system::*;
use sfml::window::*;
use sfml::graphics::*;

use crate::vn::{Answer, SceneAction};

/// Desired font size, the width should be close to a half of that value
const FONT_SIZE: u32 = 16;

pub struct RenderableAnswer<'a> {
    answer: &'a Answer,
    rect: Rect<u32>,
    renderable_text: Text<'a>
}

pub fn to_renderable_answers<'a>(window: &RenderWindow, answers: &'a Vec<Answer>, font: &'a Font) -> Vec<RenderableAnswer<'a>> {
    let win_size = window.size();

    // The offset between the things in percents, so it wouldn't directly touch the corners
    // or overlap with something
    let percents_offset = 1;

    // The pre-calculared X/Y offsets
    let (win_x_offset, win_y_offset) = (
        win_size.x / 100 * percents_offset,
        win_size.y / 100 * percents_offset
    );

    // Amount of vertical screen space in percents we have for the buttons
    let percents_vertical_space = 30;

    // Space we have
    let (starting_y, _ending_y)  = (
        win_size.y - (win_size.y / 100 * (percents_vertical_space - percents_offset)),
        win_size.y - win_y_offset
    );

    let (starting_x, ending_x) = (
        win_x_offset,
        win_size.x - win_x_offset
    );

    let (mut current_x, mut current_y) = (starting_x, starting_y);

    let mut res: Vec<RenderableAnswer> = vec![];
    for answer in answers {
        let mut text = Text::new(&answer.text, &font, FONT_SIZE);
        text.set_fill_color(&Color::BLACK);

        // Text size we initially check to see if it fits
        let beg_text_size = text.local_bounds();
        let (beg_text_width, beg_text_height) = (beg_text_size.width as u32, beg_text_size.height as u32);

        // Two offsets being an offset from the start and from the end
        let mut button_width = (win_y_offset * 3) + beg_text_width;
        let mut button_height = if res.is_empty() {
            // This is the first (or the only) button, so it will be the pattern for
            // new buttons
            (win_y_offset * 3) + beg_text_height
        } else {
            // This is not the first button, so at the beginning, take the height of the already existing button
            res.last().unwrap().rect.height
        };

        // Wraps the text to fit the screen, returns new button width and height.
        // current_x is passed as a parameter since we can't capture and modify it at the same time
        let mut wrap_text_to_fit = |current_x: u32| -> (u32, u32) {
            // Get the amount of characters that would fit on the screen
            let line_length_to_fit = (ending_x - current_x) / (FONT_SIZE / 2);
            let wrapped_text = textwrap::fill(&answer.text, line_length_to_fit as usize);
            text.set_string(&wrapped_text);
            let new_text_size = text.global_bounds();
            let (new_text_width, new_text_height) = (new_text_size.width as u32, new_text_size.height as u32);

            // Recalculate the button's width/height according to new text, updating the values for the future rect
            (
                (win_x_offset * 3) + new_text_width,
                {
                    let tmps = (win_y_offset * 3) + new_text_height;
                    // If the new resized text height is actually more than the default height, then update the height
                    if tmps > button_height { tmps } else { button_height }
                }
            )
        };

        // The button is too big to fit on the screen
        if current_x + button_width >= ending_x {
            if res.is_empty() {
                // This is either the first or the only button, so we wrap the text on the end of the screen
                // to make it fit

                let (new_bw, new_bh) = wrap_text_to_fit(current_x);

                button_width = new_bw;
                button_height = new_bh;
            } else {
                // This is not the first button and thus we can take the height of the previous button and
                // move this button down, hoping it would fit there

                let last_button = res.last().unwrap();
                let last_button_height = last_button.rect.height;

                // Move the starting X position to the beginning and the Y position to
                // the place below the last button + offset
                current_x = starting_x;
                current_y += last_button_height + win_y_offset;

                if current_x + button_width >= ending_x {
                    // The button is STILL bigger than the screen, so we'll need to wrap it

                    let (new_bw, new_bh) = wrap_text_to_fit(current_x);

                    button_width = new_bw;
                    button_height = new_bh;
                }
                // Otherwise, the size of the button rect should be fine
            }
        }

        // Move text into the rectangle, offsetting it a little, as the button was created with that in mind
        text.set_position(Vector2f::new((current_x + win_y_offset) as f32, (current_y + win_y_offset) as f32));

        res.push(
            RenderableAnswer {
                answer: answer,
                rect: Rect::new(current_x, current_y, button_width, button_height),
                renderable_text: text
            }
        );


        // Have the place for the next button
        current_x += win_x_offset + button_width;
    }

    res
}

pub fn draw_answers(window: &mut RenderWindow, renderable_answers: &Vec<RenderableAnswer>) {
    for answer in renderable_answers.iter() {
        let mut rectangle = RectangleShape::with_size(Vector2f::new(answer.rect.width as f32, answer.rect.height as f32));

        rectangle.set_position(Vector2f::new(answer.rect.left as f32, answer.rect.top as f32));
        rectangle.set_outline_color(&Color::BLACK);
        rectangle.set_outline_thickness(2.0);

        window.draw(&rectangle);
        window.draw(&answer.renderable_text);
    }
}

pub fn handle_answer_events<'a>(event: &Event, renderable_answers: &Vec<RenderableAnswer<'a>>) -> Option<&'a Vec<SceneAction>> {
    match event {
        Event::MouseButtonReleased {button: sfml::window::mouse::Button::Left , x, y } => {
            if let Some(button_index) = renderable_answers.iter().position(|a: &RenderableAnswer| a.rect.contains2(*x as u32, *y as u32)) {
                Some(&renderable_answers[button_index].answer.actions)
            } else {
                None
            }
        },
        _ => None
    }
}

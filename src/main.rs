use sfml::window::*;
use sfml::system::*;
use sfml::graphics::*;

use font_loader::system_fonts;

mod vn;
mod scene_parser;
mod term;

use crate::vn::buttons::*;
use crate::vn::*;

enum UpperPartState {
    VN,
    Terminal
}

struct State<'a> {
    current_scene: &'a Scene,
    upper_part_state: UpperPartState
}

fn main() {
    simplelog::TermLogger::init(
        if cfg!(debug_assertions) { simplelog::LevelFilter::Debug } else { simplelog::LevelFilter::Warn },
        simplelog::Config::default()
    ).unwrap();

    let mut window = RenderWindow::new(
        (1280, 1024),
        "Vacances",
        Style::CLOSE,
        &Default::default()
    );
    window.set_framerate_limit(60);

    let scenes = scene_parser::parse_scene_file("chapter_1.yml");

    let prop = system_fonts::FontPropertyBuilder::new().family("Ubuntu").build();
    let (font_data, _) = system_fonts::get(&prop).unwrap();
    let font = Font::from_memory(&font_data).unwrap();

    let mut game_state = State {
        current_scene: &scenes["start"],
        upper_part_state: UpperPartState::VN
    };

    let mut terminal_state = term::TerminalState::default();

    loop {
        let mut changed_scene = None;
        let renderable_answers = to_renderable_answers(
            &window,
            &game_state.current_scene.answers,
            &font
        );

        while let Some(event) = window.poll_event() {
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

            match game_state.upper_part_state {
                UpperPartState::VN => {
                    if let Some(bes) = handle_answer_events(&event, &renderable_answers) {
                        for be in bes  {
                            match be {
                                SceneAction::ChangeScene(new_scene) => changed_scene = Some(&scenes[new_scene]),
                                SceneAction::OpenTerminal(term) => { game_state.upper_part_state = UpperPartState::Terminal; }
                            }
                        }
                    }
                }

                UpperPartState::Terminal => {
                    term::handle_term_events(&event, &mut terminal_state);
                }
            }
        }

        window.clear(&Color::WHITE);

        match game_state.upper_part_state {
            UpperPartState::VN => {
                vn::draw_text_frame(&mut window, &game_state.current_scene, &font);
                draw_answers(
                    &mut window,
                    &renderable_answers
                );

                if changed_scene.is_some() { game_state.current_scene = changed_scene.unwrap(); }
            }

            UpperPartState::Terminal => {
                term::draw_terminal(&mut window, &font, &mut terminal_state);
            }
        }

        window.display();
    }
}

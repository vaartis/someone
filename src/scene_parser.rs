use std::collections::BTreeMap;

use serde_derive::Deserialize;

use crate::vn::{Answer, Scene, SceneAction};
use log::debug;

#[derive(rust_embed::RustEmbed)]
#[folder = "scenes"]
struct Scenes;

#[derive(Debug, Deserialize)]
struct ParsedScene {
    /// Scene text
    text: String,
    /// Possible answers to the scene, if left empty, becomes "Next" pointing to the scene-nameN+1
    #[serde(default = "BTreeMap::new")]
    answers: BTreeMap<String, BTreeMap<String, String>>,
    /// When parsing the entry, import these files and parse them before that one
    import: Option<Vec<String>>
}

pub fn parse_scene_file(file_name: &str) -> BTreeMap<String, Scene> {
    let text_utf = Scenes::get(file_name).unwrap();
    let text = std::str::from_utf8(&text_utf).unwrap();

    let parsed: BTreeMap<String, ParsedScene> = serde_yaml::from_str(text).unwrap();

    let mut scenes = BTreeMap::new();

    for (scene_name, mut scene) in parsed {

        if let Some(imported_files) = scene.import {
            for imported_file in imported_files {
                debug!("Loading scene file {}.yml for scene {} from {}", imported_file, scene_name, file_name);

                scenes.append(
                    &mut parse_scene_file(&format!("{}.yml", imported_file))
                );
            }
        }

        // If no answers are provided, just assume "Next"
        if scene.answers.is_empty() {
            scene.answers.insert("Next".to_string(), BTreeMap::new());
        }

        let actual_answers = scene.answers.iter().map(|a: (&String, &BTreeMap<String, String>)| {
            let (answer_text, actions) = a;

            let actions = {
                // A shortcut to get to the next numbered scene
                if actions.is_empty() {
                    let regex = regex::Regex::new(r"\d+$").unwrap();
                    let fnd = regex.find(&scene_name);
                    let name_wo_num = if fnd.is_none() { &scene_name } else { &scene_name[..fnd.unwrap().start()] };
                    let num = if fnd.is_none() { 1 } else { scene_name[fnd.unwrap().start()..fnd.unwrap().end()].parse::<u32>().unwrap()  };
                    vec![ SceneAction::ChangeScene(format!("{}{}", name_wo_num, num + 1)) ]
                } else {
                    actions.iter().map(|ac: (&String, &String)| {
                        match ac.0.as_str() {
                            "SCENE" => SceneAction::ChangeScene(ac.1.to_string()),
                            "TERM" => SceneAction::OpenTerminal(ac.1.to_string()),
                            _ => panic!("Invalid action in scene {}", scene_name)
                        }
                    }).collect::<Vec<_>>()
                }
            };
            
            Answer {
                text: answer_text.to_string(),
                actions: actions
            }
        }).collect::<Vec<_>>();

        scenes.insert(scene_name, Scene { text: scene.text.clone(), answers: actual_answers });
    }

    scenes
}

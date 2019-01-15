use std::collections::BTreeMap;

use serde_derive::Deserialize;

use crate::vn::{Answer, Scene, SceneAction};

#[derive(Debug, Deserialize)]
struct ParsedScene {
    text: String,
    #[serde(default = "BTreeMap::new")]
    answers: BTreeMap<String, BTreeMap<String, String>>
}

pub fn parse_scene_file(text: &str) -> BTreeMap<String, Scene> {
    let mut parsed: BTreeMap<String, ParsedScene> = serde_yaml::from_str(text).unwrap();

    parsed.iter_mut().map(|v: (&String, &mut ParsedScene)| {
        let (scene_name, scene) = v;
        if scene.answers.is_empty() {
            // If no answers are provided, just assume "Next"
            scene.answers.insert("Next".to_string(), BTreeMap::new());
        }
        
        let actual_answers = scene.answers.iter().map(|a: (&String, &BTreeMap<String, String>)| {
            let (answer_text, actions) = a;

            let actions = {
                // A shortcut to get to the next numbered scene
                if actions.is_empty() {
                    let regex = regex::Regex::new(r"\d+$").unwrap();
                    let fnd = regex.find(scene_name);
                    let name_wo_num = if fnd.is_none() { scene_name } else { &scene_name[..fnd.unwrap().start()] };
                    let num = if fnd.is_none() { 1 } else { scene_name[fnd.unwrap().start()..fnd.unwrap().end()].parse::<u32>().unwrap()  };
                    vec![ SceneAction::ChangeScene(format!("{}{}", name_wo_num, num + 1)) ]
                } else {
                    actions.iter().map(|ac: (&String, &String)| {
                        match ac.0.as_str() {
                            "SCENE" => SceneAction::ChangeScene(ac.1.to_string()),
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

        (
            scene_name.clone(),
            Scene { text: scene.text.clone(), answers: actual_answers }
        )
    }).collect::<BTreeMap<_,_>>()
}

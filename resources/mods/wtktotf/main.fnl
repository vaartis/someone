(local lume (require "lume"))
(local util (require "util"))
(local collider-components (require "components.collider"))
(local assets (require "components.assets"))

(local M {})

(local is-debug false)

(set M.music-settings
     {:since-last-mute 1
      :since-last-change 0.2
      :saved-volume 30
      :volume 30

      :sfx-volume 100})

(set
 M.components
 {
  :paralax {:class (Component.create "Paralax" ["speed" "variants"])}
  :attack_data {:class (Component.create "AttackData" ["time-since-last-attack"] {:time-since-last-attack 1})}
  :hit_data {:class (Component.create "HitData" ["velocity"])}
  :player_data {:class (Component.create "PlayerData" ["lost" "jump-velocity" "frames-touching" "score" "since-last-score"]
                                         {:lost false :jump-velocity 0 :frames-touching 0
                                          :score 0 :since-last-score 0})}})

(fn M.components.paralax.process_component [new-ent comp entity-name]
  (new-ent:add (M.components.paralax.class comp.speed comp.variants)))

(fn M.components.attack_data.process_component [new-ent comp entity-name]
  (new-ent:add (M.components.attack_data.class)))

(fn M.components.hit_data.process_component [new-ent comp entity-name]
  (new-ent:add (M.components.hit_data.class)))

(fn M.components.player_data.process_component [new-ent comp entity-name]
  (new-ent:add (M.components.player_data.class)))

(fn did-lose []
  (let [rooms (util.rooms_mod)
        player (util.first (rooms.engine:getEntitiesWithComponent "PlayerData"))]
    (when player
      (let [data (player:get "PlayerData")]
        data.lost))))

(fn reset-touch []
  (let [rooms (util.rooms_mod)]
    (each [_ player (pairs (rooms.engine:getEntitiesWithComponent "PlayerData"))]
      (let [data (player:get "PlayerData")]
        (set data.frames-touching 0)))))

(local ParalaxSystem (class "ParalaxSystem" System))
(fn ParalaxSystem.requires [] ["Paralax"])
(fn ParalaxSystem.update [self]
  (when (did-lose)
    (lua :return))

  (each [_ entity (pairs self.targets)]
    (let [tf (. (entity:get "Transformable") :transformable)
          drawable (. (entity:get "Drawable") :drawable)
          paralax (entity:get "Paralax")]
      (set tf.position (- tf.position (Vector2f.new paralax.speed 0)))

      (let [screen-size GLOBAL.drawing_target.size.x]
        (when (< tf.position.x (- drawable.global_bounds.width))
          ;; When outside of the screen, move back
          (set tf.position.x drawable.global_bounds.width)

          (when paralax.variants
            ;; Choose a random new texture
            (math.randomseed (os.time))
            (set drawable.texture
                 (. assets.assets.textures (lume.randomchoice paralax.variants)))))))))

(local AttackDataSystem (class "AttackDataSystem" System))
(fn AttackDataSystem.requires [] ["AttackData"])
(fn AttackDataSystem.update [self dt]
  (each [_ entity (pairs self.targets)]
    (let [attack-data (entity:get "AttackData")]
      (set attack-data.time-since-last-attack (+ attack-data.time-since-last-attack dt)))))

(local AttackSystem (class "AttackSystem" System))
(fn AttackSystem.requires []
  { :player ["PlayerTag" "AttackData"] :player-attack ["PlayerAttackTag"]})
(fn AttackSystem.draw [self]
  (each [_ player (pairs self.targets.player)]
    (let [attack (util.first self.targets.player-attack)

          player-drawable (player:get "Drawable")
          attack-drawable (attack:get "Drawable")
          attack-animation (attack:get "Animation")

          attacking attack-animation.playing

          attack-data (player:get "AttackData")
          can-attack-already (> attack-data.time-since-last-attack 1)]

      (when attack-animation.playing
        (let [curr-frame (. attack-animation.frames attack-animation.current_frame)
              curr-frame-tags curr-frame.tags]
          (when (and curr-frame-tags (lume.find curr-frame-tags "damage"))
            ;; Damage frames

            (let [physics-world collider-components.physics_world
                  (x y w h) (physics-world:getRect player)
                  (check-x check-y) (values (+ x w 10) (+ y (/ h 2)))
                  (check-w check-h) (values 70 70)]
              (when is-debug
                (let [shape (RectangleShape.new (Vector2f.new check-w check-h))]
                  (doto shape
                    (tset :outline_thickness 3.0)
                    (tset :outline_color Color.Red)
                    (tset :fill_color Color.Red)
                    (tset :position (Vector2f.new check-x check-y))

                    (GLOBAL.drawing_target:draw))))

              (let [(items len) (physics-world:queryRect check-x check-y check-w check-h (fn [ent] (ent:get "EnemyTag")))]
                (when (> len 0)
                  (let [enemy-ent (util.first items)
                        enemy-hit-ent (lume.match enemy-ent.children (fn [child] (child:get "EnemyHitTag")))
                        enemy-hit-drawable (enemy-hit-ent:get "Drawable")]
                    (let [rooms (util.rooms_mod)]
                      ;; Play the hit sound
                      (M.sound-effects.hit:play)

                      ;; Reset touching
                      (reset-touch)

                      ;; Delete the enemy itself
                      (rooms.engine:removeEntity enemy-ent))

                    (set enemy-hit-drawable.enabled true))))))))

      (if (and (Keyboard.is_key_pressed KeyboardKey.X) (not attacking) can-attack-already (not (did-lose)))
          (do
            (set attack-data.time-since-last-attack 0)

            ;; Enable attack animation
            (set attack-drawable.enabled true)
            ;; Disable main sprite
            (set player-drawable.enabled false)
            ;; Start the animation
            (set attack-animation.playing true))

          (= attack-animation.current_frame (length attack-animation.frames))
          (do
            ;; Disable animation
            (set attack-animation.playing false)
            ;; Reset the frame
            (set attack-animation.current_frame 1)

            ;; Disable attack drawable
            (set attack-drawable.enabled false)
            ;; Enable the player drawable again
            (set player-drawable.enabled true))))))

(local possible-obstacles
       [{
         :name "obstacle1"
         :entity {
                  :prefab "obstacle1"
                  :transformable { :position [ 1280 718 ] } } }
        {
         :name "obstacle2"
         :entity {
                  :prefab "obstacle2"
                  :transformable { :position [ 1280 756 ] } } }])

(local possible-enemies
       [
        {:name "enemy1"
         :entity {:prefab "enemy1"
                  :transformable {:position [ 1280 665 ]} }}
        {:name "enemy2"
         :entity {:prefab "enemy2"
                  :transformable { :position [ 1280 696 ] } }}
        {:name "enemy3"
         :entity {:prefab "enemy3"
                  :transformable { :position [ 1280 700 ] } }}])

(local EnemySpawnerSytem (class "EnemySpawnerSystem" System))
(fn EnemySpawnerSytem.requires []
  {:enemy ["EnemyTag"] :enemy-hit [ "EnemyHitTag" ] :obstacle ["ObstacleTag"]
   :spawner ["SpawnerTag"]})
(fn EnemySpawnerSytem.update [self dt]
  (when (did-lose)
    (lua :return))

  (each [_ _ (pairs self.targets.spawner)]
    (let [enemy-ent (util.first self.targets.enemy)
          enemy-ent-hit (util.first self.targets.enemy-hit)
          obstacle-ent (util.first self.targets.obstacle)]
      ;; When there are no enemies/obstacles, spawn one
      (when (and (not enemy-ent) (not enemy-ent-hit) (not obstacle-ent))
        (math.randomseed (os.time))
        (let [entities (util.entities_mod)
              possible-spawners (lume.randomchoice [ possible-enemies possible-obstacles ])
              {: name : entity} (lume.randomchoice possible-spawners)]
          (entities.instantiate_entity name entity))))))

(fn when-lost [collision]
  (let [player-ent collision.other
        player-data (player-ent:get "PlayerData")
        player-animation (player-ent:get "Animation")
        player-drawable (player-ent:get "Drawable")

        player-lost (lume.match player-ent.children (fn [child] (child:get "PlayerLostTag")))
        player-lost-animation (player-lost:get "Animation")
        player-lost-drawable (player-lost:get "Drawable")

        {:x touch-x :y touch-y} collision.touch]
    ;; Disable main animation & sprite
    (set player-animation.playing false)
    (set player-drawable.enabled false)

    ;; Enable lost animation
    (set player-lost-drawable.enabled true)
    (set player-lost-animation.playing true)

    ;; Spawn an explosion
    (let [entities (util.entities_mod)]
      (entities.instantiate_entity "explosion" { :prefab "explosion"
                                                :transformable { :position [ touch-x touch-y ]} }))
    ;; Play the explosion sound
    (M.sound-effects.explosion:play)

    (set player-data.lost true)))

(local EnemyHitSystem (class "EnemyHitSystem" System))
(fn EnemyHitSystem.requires []
  { :enemy ["EnemyTag"] :enemy-hit [ "EnemyHitTag" ]})
(fn EnemyHitSystem.update [self dt]
  (each [_ enemy-hit-ent (pairs self.targets.enemy-hit)]
    (let [enemy-hit-drawable (enemy-hit-ent:get "Drawable")
          enemy-hit-tf (enemy-hit-ent:get "Transformable")

          hit-data (enemy-hit-ent:get "HitData")

          physics-world collider-components.physics_world]

      (if enemy-hit-drawable.enabled
          ;; if hit, enemy is flying away
          (do
            ;; Enemy velocity is not set yet
            (when (not hit-data.velocity)
              (math.randomseed (os.time))
              (set hit-data.velocity (Vector2f.new (lume.random 0.6 1) (lume.random 0.3 0.8)))
              ;; Normalize direction vector
              (let [velocity hit-data.velocity
                    vec-len (+ (* velocity.x velocity.x) (* velocity.y velocity.y))]
                (set hit-data.velocity.x (/ velocity.x vec-len))
                (set hit-data.velocity.y (/ velocity.y vec-len))))

            (let [tf enemy-hit-tf.transformable
                  (x y) (values tf.position.x tf.position.y)]
              (set tf.position (Vector2f.new (+ x (* hit-data.velocity.x 10))
                                             (- y (* hit-data.velocity.y 10))))

              (when (or (> x 1280) (< x -300) (< y -300))
                ;; Remove entity when it's outside of the screen
                (let [rooms (util.rooms_mod)]
                  (rooms.engine:removeEntity enemy-hit-ent)))))

          ;; else, non-hit enemy moving to the player
          (each [_ enemy-ent (pairs self.targets.enemy)]
            ;; Stop moving if lost
            (when (did-lose)
              (lua :return))

            (let [(x y w h) (physics-world:getRect enemy-ent)
                  (_ _ cols len) (physics-world:move enemy-ent (- x 10) y (fn [ent] "touch"))]
              (when (> len 0)
                ;; Hit the player
                (let [collision (util.first cols)
                      player-ent collision.other
                      player-data (player-ent:get "PlayerData")

                      enemy-animation (enemy-ent:get "Animation")]

                  (if (< player-data.frames-touching 15)
                      (set player-data.frames-touching (+ player-data.frames-touching 1))
                      ;; Touched for too long, lose
                      (do
                        ;; Disable player animation
                        (when-lost collision)
                        ;; Disable enemy animation
                        (set enemy-animation.playing false)))))))))))

(local ObstacleSystem (class "ObstacleSystem" System))
(fn ObstacleSystem.requires [] ["ObstacleTag"] )
(fn ObstacleSystem.update [self dt]
  ;; Stop moving if lost
  (when (did-lose)
    (lua :return))

  (each [_ entity (pairs self.targets)]
    (let [obstacle-collider (entity:get "Collider")

          physics-world collider-components.physics_world]
      (let [(x y w h) (physics-world:getRect entity)
            (_ _ cols len) (physics-world:move entity (- x 10) y (fn [ent] "touch"))]
        (when (> len 0)
          (when-lost (util.first cols)))

        (when (< x -300)
          (let [rooms (util.rooms_mod)]
            ;; Delete the obstacle
            (rooms.engine:removeEntity entity)))))))

(local JumpSystem (class "JumpSystem" System))
(fn JumpSystem.requires []
  { :player ["PlayerTag"] :player-attack ["PlayerAttackTag"] :enemy ["EnemyTag"] })
(fn JumpSystem.update [self dt]
  (each [_ player-ent (pairs self.targets.player)]
    (let [player-attack-ent (util.first self.targets.player-attack)

          player-data (player-ent:get "PlayerData")
          player-attack-animation (player-attack-ent:get "Animation")
          is-attacking player-attack-animation.playing

          physics-world collider-components.physics_world
          (x y w h) (physics-world:getRect player-ent)

          max-velocity 8
          gravity 0.1]

      (when (and (not is-attacking)
                 (= player-data.jump-velocity 0)
                 ;; Make sure the player doesn't jump at the very start, right after the Z press in the menu
                 (> player-data.score 5)
                 (Keyboard.is_key_pressed KeyboardKey.Z)
                 (not (did-lose)))
        ;; Play the jump sound
        (M.sound-effects.jump:play)

        (set player-data.jump-velocity max-velocity))

      (when (not (= player-data.jump-velocity 0))
        (set player-data.jump-velocity (- player-data.jump-velocity gravity))

        (physics-world:move player-ent x (- y player-data.jump-velocity))
        (each [_ enemy (pairs self.targets.enemy)]
          (let [(enemy-x enemy-y _ _) (physics-world:getRect enemy)]
            (physics-world:move enemy enemy-x (- enemy-y player-data.jump-velocity)))))

      (when (> (- y player-data.jump-velocity) 570)
        ;; Play the landing sound
        (M.sound-effects.landing:play)

        (set player-data.jump-velocity 0)
        (physics-world:move player-ent x 570))

      (each [_ enemy (pairs self.targets.enemy)]
        (let [name (. (enemy:get "Name") :name)
              initial-data (lume.match possible-enemies
                                       (fn [enemy]
                                         (= enemy.name name)))
              ground-y (. initial-data.entity.transformable.position 2)

              (enemy-x enemy-y _ _) (physics-world:getRect enemy)]
          (when (> (- enemy-y player-data.jump-velocity) ground-y)
            (physics-world:move enemy enemy-x ground-y)))))))

(local LostSystem (class "LostSystem" System))
(fn LostSystem.requires [] [ "LostTextTag" ])
(fn LostSystem.update [self dt]
  (when (did-lose)
    (let [lost-text (util.first self.targets)]
      (if lost-text
          ;; Handle the restarting
          (when (Keyboard.is_key_pressed KeyboardKey.R)
            (let [rooms (util.rooms_mod)]
              (rooms.load_room "wtktotf_menu")))

          ;; Spawn the text
          (let [entities (util.entities_mod)]
            (entities.instantiate_entity "lost-text" { :prefab "lost-text" }))))))

(local ScoreSystem (class "ScoreSystem" System))
(fn ScoreSystem.requires [] { :text ["ScoreTextTag"] :player ["PlayerData"] })
(fn ScoreSystem.update [self dt]
  (each [_ player (pairs self.targets.player)]
    (let [text (util.first self.targets.text)

          player-data (player:get "PlayerData")
          text-drawable (text:get "Drawable")]
      (when (not (did-lose))
        (set player-data.since-last-score (+ player-data.since-last-score dt))

        (when (> player-data.since-last-score 0.1)
          (set player-data.since-last-score 0)
          (set player-data.score (+ player-data.score 1))

          (set text-drawable.drawable.string (lume.format "{1} meters" [player-data.score])))))))

(local ExplosionSystem (class "ExplosionSystem" System))
(fn ExplosionSystem.requires [] ["ExplosionTag"])
(fn ExplosionSystem.update [self dt]
  (each [_ ent (pairs self.targets)]
    (let [animation (ent:get "Animation")]
      (when (and (not animation.playing) (= animation.current_frame (length animation.frames)))
        ;; Animation finished, destroy the explosion
        (let [rooms (util.rooms_mod)]
          (rooms.engine:removeEntity ent))))))

(local VolumeControlSystem (class "VolumeControlSystem" System))
(fn VolumeControlSystem.requires [] [])
(fn VolumeControlSystem.update [self dt]
  (set M.music-settings.since-last-mute (+ M.music-settings.since-last-mute dt))
  (set M.music-settings.since-last-change (+ M.music-settings.since-last-change dt))

  (var volume-changed false)
  (var sfx-volume-changed false)

  ;; Mute/Unmute
  (when (and (Keyboard.is_key_pressed KeyboardKey.M) (> M.music-settings.since-last-mute 1))
    (set M.music-settings.volume
         (if (= M.music-settings.volume 0) M.music-settings.saved-volume 0))

    (set volume-changed true))

  (if
   ;; SFX volume up
   (and (Keyboard.is_key_pressed KeyboardKey.Q) (Keyboard.is_key_pressed KeyboardKey.LShift)
        (> M.music-settings.since-last-change 0.2))
   (do
     (set M.music-settings.sfx-volume (lume.clamp (- M.music-settings.sfx-volume 10) 0 100))

     (set sfx-volume-changed true))
   ;; SFX volume down
   (and (Keyboard.is_key_pressed KeyboardKey.E) (Keyboard.is_key_pressed KeyboardKey.LShift)
        (> M.music-settings.since-last-change 0.2))
   (do
     (set M.music-settings.sfx-volume (lume.clamp (+ M.music-settings.sfx-volume 10) 0 100))

     (set sfx-volume-changed true))

   ;; Volume up
   (and (Keyboard.is_key_pressed KeyboardKey.Q) (> M.music-settings.since-last-change 0.2))
   (do
     (set M.music-settings.volume (lume.clamp (- M.music-settings.volume 10) 0 100))
     (set M.music-settings.saved-volume M.music-settings.volume)

     (set volume-changed true))
   ;; Volume down
   (and (Keyboard.is_key_pressed KeyboardKey.E) (> M.music-settings.since-last-change 0.2))
   (do
     (set M.music-settings.volume (lume.clamp (+ M.music-settings.volume 10) 0 100))
     (set M.music-settings.saved-volume M.music-settings.volume)

     (set volume-changed true)))

  (when (or volume-changed sfx-volume-changed)
    (set M.music-settings.since-last-mute 0)
    (set M.music-settings.since-last-change 0)

    (if
     volume-changed
     (set M.music.volume M.music-settings.volume)

     sfx-volume-changed
     (do
       (each [_ effect (pairs M.sound-effects)]
         (tset effect :volume M.music-settings.sfx-volume))
       ;; Play an example
       (M.sound-effects.hit:play)))

    ;; Actually defined in terminal.lua as global..
    (show_info_message
     (if
      volume-changed
      (lume.format "Volume {1}%" [M.music-settings.volume])

      sfx-volume-changed
      (lume.format "SFX volume {1}%" [M.music-settings.sfx-volume]))
     {:font_size 48 :font_color (Color.new 255 255 255 0)})))


(local MenuSystem (class "MenuSystem" System))
(fn MenuSystem.requires [] ["MenuTag"])
(fn MenuSystem.update [self dt]
  (each [_ _ (pairs self.targets)]
    ;; Start the game
    (when (and (Keyboard.is_key_pressed KeyboardKey.Z))
      (let [rooms (util.rooms_mod)]
        (rooms.load_room "wtktotf")))))

(set M.systems [
                ParalaxSystem AttackDataSystem EnemySpawnerSytem EnemyHitSystem AttackSystem ObstacleSystem JumpSystem
                LostSystem ScoreSystem ExplosionSystem VolumeControlSystem MenuSystem ])


;; Make the sound always play
(let [sound (assets.create_sound_from_asset "mod.gamejam1")]
  (doto sound
    (tset :loop true)
    (tset :volume M.music-settings.volume)
    (: :play))
  (set M.music sound)

  (set M.sound-effects {:explosion (assets.create_sound_from_asset "mod.explosion")
                        :jump (assets.create_sound_from_asset "mod.jump")
                        :hit (assets.create_sound_from_asset "mod.hit")
                        :landing (assets.create_sound_from_asset "mod.landing")}))

M

/**
 * @file scenes.d
 * @brief scene system for menu, play, and editor screens
 *
 * each scene handles its own input, update, and draw calls.
 */
module scenes;

import std.stdio;
import std.file;
import std.string;
import std.conv;
import std.math;
import std.algorithm;
import std.array;
import std.format : format;
import std.json : JSONType;

import bindbc.sdl;

import component;
import gameobject;
import resourcemanager;
import tilemap;
import scripts;

/// \struct SceneRequest
/// \brief small message used to ask the app to change scenes
struct SceneRequest {
    bool pending = false;
    string target;
    string payload;
}

/// \class SceneBase
/// \brief base class with a shared resource manager and window size
class SceneBase {
protected:
    ResourceManager resources;
    int windowW;
    int windowH;
private:
    SceneRequest request;
public:
    /// store shared resource manager and window size
    this(ResourceManager res, int w, int h){
        resources = res;
        windowW = w;
        windowH = h;
    }

    /// handle input events (override in derived scenes)
    void HandleEvent(ref SDL_Event){}
    /// poll keyboard / mouse state (override in derived scenes)
    void Input(){}
    /// update game state (override in derived scenes)
    void Update(float){}
    /// draw the scene (override in derived scenes)
    void Render(SDL_Renderer*){}
    /// called when a scene becomes active
    void OnEnter(){}
    /// called when a scene is no longer active
    void OnExit(){}

    /// get the current request and clear it
    SceneRequest ConsumeRequest(){
        auto result = request;
        request = SceneRequest();
        return result;
    }
protected:
    /// ask the application to switch to another scene
    void RequestSwitch(string target, string payload = ""){
        request.pending = true;
        request.target = target;
        request.payload = payload;
    }
}

/// \class MenuScene
/// \brief simple menu where the user picks a level or editor
class MenuScene : SceneBase {
private:
    LevelEntry[] levels;
    int highlight = 0;
    float pulse = 0;
public:
    /// set up the menu scene with shared resources
    this(ResourceManager res, int w, int h){
        super(res, w, h);
    }

    /// reload the list of levels when entering the menu
    override void OnEnter(){
        levels = resources.Levels();
        highlight = 0;
        pulse = 0;
    }

    /// handle key presses for menu navigation and selection
    override void HandleEvent(ref SDL_Event e){
        if (e.type == SDL_EVENT_KEY_DOWN){
            auto sym = e.key.key;
            if (sym >= SDLK_1 && sym <= SDLK_9){
                int idx = cast(int)sym - cast(int)SDLK_1;
                if (idx >= 0 && idx < cast(int)levels.length){
                    RequestSwitch("play", levels[idx].id);
                }
            } else if (sym == SDLK_E){
                RequestSwitch("editor");
            } else if (sym == SDLK_ESCAPE){
                RequestSwitch("quit");
            } else if (sym == SDLK_DOWN){
                CycleHighlight(1);
            } else if (sym == SDLK_UP){
                CycleHighlight(-1);
            } else if (sym == SDLK_RETURN || sym == SDLK_KP_ENTER){
                if (levels.length > 0){
                    RequestSwitch("play", levels[highlight].id);
                }
            }
        }
    }

    /// update simple animation timers
    override void Update(float dt){
        pulse += dt * 2.0f;
    }

    /// draw the level list and help text
    override void Render(SDL_Renderer* renderer){
        SDL_SetRenderDrawColor(renderer, 16, 18, 24, 255);
        SDL_RenderClear(renderer);
        
        // Center the menu
        float totalHeight = levels.length * 95;
        float startY = (windowH - totalHeight) * 0.5f;
        if (startY < 40) startY = 40;
        
        float itemWidth = 600;
        float startX = (windowW - itemWidth) * 0.5f;
        
        foreach (i, level; levels){
            float y = startY + i * 95;
            SDL_FRect rect;
            rect.x = startX;
            rect.y = y;
            rect.w = itemWidth;
            rect.h = 80;
            bool active = highlight == cast(int)i;

            auto btnColor = active ? makeColor(60, 100, 180, 255) : makeColor(30, 35, 45, 255);
            SDL_SetRenderDrawColor(renderer, btnColor.r, btnColor.g, btnColor.b, btnColor.a);
            SDL_RenderFillRect(renderer, &rect);
            
            SDL_Color borderColor = active ? makeColor(100, 180, 255, 255) : makeColor(50, 60, 70, 255);
            drawRectOutline(renderer, rect, borderColor);
            
            SDL_Color textColor;
            textColor.r = 220; textColor.g = 220; textColor.b = 230; textColor.a = 255;
            string title = level.title.length ? level.title.toUpper() : level.id.toUpper();
            
            float textX = rect.x + 20;
            drawText(renderer, textX, rect.y + 35, format("%d. %s", i + 1, title), textColor);
        }
        if (levels.length == 0){
            drawText(renderer, startX, startY, "NO LEVELS");
        }
        
        SDL_Color helpColor;
        helpColor.r = 100; helpColor.g = 100; helpColor.b = 120; helpColor.a = 255;
        drawText(renderer, 40, windowH - 25, "E: LEVEL EDITOR  |  ESC: QUIT", helpColor);
    }
private:
    /// move the highlighted menu entry up or down
    void CycleHighlight(int delta){
        if (levels.length == 0){
            return;
        }
        highlight = (highlight + delta) % cast(int)levels.length;
        if (highlight < 0){
            highlight = cast(int)levels.length - 1;
        }
    }
}

/// \class PlayScene
/// \brief main gameplay scene that runs the player and tile map
class PlayScene : SceneBase, IPlayerWorld {
private:
    TileMap map;
    GameObject player;
    PlayerScript playerScript;
    GameObject[] traps;
    GameObject[] projectiles;
    float camX = 0;
    float camY = 0;
    bool revealSecrets = false;
    bool playerAlive = false;
    float respawnTimer = 0;
    bool levelComplete = false;
    float completeTimer = 0;
    string levelId;
    string levelTitle;
public:
    /// build a play scene with shared resources
    this(ResourceManager res, int w, int h){
        super(res, w, h);
    }

    /// load a level by id and reset player state
    bool LoadLevel(string id){
        auto level = resources.FindLevel(id);
        if (level is null){
            return false;
        }
        auto tileSet = resources.Tiles();
        if (tileSet is null){
            return false;
        }
        auto json = resources.LoadLevelJSON(level.file);
        map = new TileMap(tileSet);
        map.SetTextureLoader((path){
            if (resources is null || path.length == 0){
                return cast(SDL_Texture*)null;
            }
            return resources.LoadTexture(path);
        });
        map.LoadFromJSON(json);
        levelId = level.id;
        levelTitle = level.title.length ? level.title.toUpper() : level.id.toUpper();
        SetupPlayer();
        SpawnTraps();
        projectiles = [];
        revealSecrets = false;
        playerAlive = true;
        levelComplete = false;
        completeTimer = 0;
        return true;
    }

    /// handle hotkeys during gameplay
    override void HandleEvent(ref SDL_Event e){
        if (e.type == SDL_EVENT_KEY_DOWN){
            auto sym = e.key.key;
            if (sym >= SDLK_1 && sym <= SDLK_9){
                int idx = cast(int)sym - cast(int)SDLK_1;
                if (playerScript !is null){
                    playerScript.SelectSlot(idx);
                }
            } else if (sym == SDLK_LEFTBRACKET){
                if (playerScript !is null) playerScript.CycleSelection(-1);
            } else if (sym == SDLK_RIGHTBRACKET){
                if (playerScript !is null) playerScript.CycleSelection(1);
            } else if (sym == SDLK_TAB){
                revealSecrets = !revealSecrets;
            } else if (sym == SDLK_ESCAPE){
                RequestSwitch("menu");
            } else if (sym == SDLK_R){
                RespawnPlayer();
            } else if (sym == SDLK_Q){
                ResetLevel();
            } else if (sym == SDLK_E || sym == SDLK_F){
                TryPlaceBlockInFront();
            }
        }
    }

    /// update player, traps, projectiles, and camera
    override void Update(float dt){
        if (playerAlive && player !is null){
            player.Input();
            player.Update(dt);
            ProcessPlayerState();
        } else {
            respawnTimer -= dt;
            if (respawnTimer <= 0){
                RespawnPlayer();
            }
        }
        foreach (trap; traps){
            if (trap.alive){
                trap.Input();
                trap.Update(dt);
            }
        }
        foreach (proj; projectiles){
            if (proj.alive){
                proj.Input();
                proj.Update(dt);
            }
        }
        projectiles = projectiles.filter!(p => p.alive).array;
        UpdateCamera();
    }

    /// draw map, player, traps, projectiles, and hud
    override void Render(SDL_Renderer* renderer){
        SDL_SetRenderDrawColor(renderer, 12, 14, 18, 255);
        SDL_RenderClear(renderer);
        if (map is null){
            drawText(renderer, 20, 20, "NO MAP");
            return;
        }
        map.Render(renderer, camX, camY, windowW, windowH - 80, revealSecrets, false, false, -1, -1);
        if (player !is null){
            RenderPlayer(renderer);
        }
        foreach (trap; traps){
            trap.Render(renderer, camX, camY);
        }
        foreach (proj; projectiles){
            proj.Render(renderer, camX, camY);
        }
        DrawHUD(renderer);
    }

    /// move the player within the tile map and clamp to solids
    MovementResult ResolvePlayerMovement(GameObject go, JumpComponent rb, float dt){
        MovementResult result;
        if (map is null){
            return result;
        }
        auto tr = go.GetComponentAs!TransformComponent(COMPONENTS.TRANSFORM);
        if (tr is null){
            return result;
        }
        SDL_FRect rect = tr.rect;
        float dx = rb.vx * dt;
        rect.x += dx;
        
        // x collision, shrink y to avoid catching the floor/ceiling
        SDL_FRect xCheckRect = rect;
        xCheckRect.y += 4.0f; 
        xCheckRect.h -= 8.0f;
        
        if (map.RectHitsSolid(xCheckRect)){
            if (dx > 0){
                float right = rect.x + rect.w;
                int tileX = cast(int)floor(right / map.TileSize());
                rect.x = tileX * map.TileSize() - rect.w - 0.001f;
            } else if (dx < 0){
                int tileX = cast(int)floor(rect.x / map.TileSize());
                rect.x = (tileX + 1) * map.TileSize() + 0.001f;
            }
            rb.vx = 0;
        }

        float dy = rb.vy * dt;
        rect.y += dy;
        bool grounded = false;

        if (map.RectHitsSolid(rect)){
            if (dy > 0){
                float bottom = rect.y + rect.h;
                int tileY = cast(int)floor(bottom / map.TileSize());
                rect.y = tileY * map.TileSize() - rect.h - 0.001f;
                grounded = true;
            } else if (dy < 0){
                int tileY = cast(int)floor(rect.y / map.TileSize());
                rect.y = (tileY + 1) * map.TileSize() + 0.001f;
            }
            rb.vy = 0;
        }
        tr.rect = rect;
        result.grounded = grounded;
        result.surface = map.SurfaceInfoFor(rect);
        return result;
    }

    /// get the player's world rectangle or an empty rect
    SDL_FRect PlayerRect(){
        SDL_FRect rect;
        if (player is null){
            rect.x = rect.y = rect.w = rect.h = 0;
            return rect;
        }
        auto tr = player.GetComponentAs!TransformComponent(COMPONENTS.TRANSFORM);
        if (tr is null){
            rect.x = rect.y = rect.w = rect.h = 0;
            return rect;
        }
        return tr.rect;
    }

    /// mark the player as dead and start the respawn timer
    void KillPlayer(string reason){
        if (!playerAlive){
            return;
        }
        playerAlive = false;
        respawnTimer = 1.0f;
        if (playerScript !is null){
            playerScript.SetAlive(false);
        }
    }
private:
    /// create player object, components, and inventory
    void SetupPlayer(){
        player = new GameObject();
        auto spawn = map.SpawnRect();

        float playerWidth = 14.0f;
        float playerHeight = 30.0f;
        float playerX = spawn.x + (spawn.w - playerWidth) * 0.5f;
        float playerY = spawn.y + spawn.h - playerHeight;
        auto tr = new TransformComponent(playerX, playerY, playerWidth, playerHeight);
        player.AddComponent(COMPONENTS.TRANSFORM, tr);
        auto playerTexture = RequireTexture("player_sprite", "Assets/sprites/player.bmp");

        if (playerTexture !is null){
            auto tex = new TextureComponent(playerTexture);
            player.AddComponent(COMPONENTS.TEXTURE, tex);
            
            auto animData = resources.GetAnimationData("player");
            if (animData.type != JSONType.null_){
                auto anim = new AnimationComponent(animData);
                player.AddComponent(COMPONENTS.ANIMATION, anim);
               
                anim.PlayAnimation("idle");
                anim.SetInitialFrame(tex);
            }
        } else {
            auto color = new ColorComponent(70, 180, 255, 255);
            player.AddComponent(COMPONENTS.COLOR, color);
        }
        auto rb = new JumpComponent();
        player.AddComponent(COMPONENTS.JUMP, rb);
        playerScript = new PlayerScript();
        player.AddScript(playerScript, cast(Object)this);
        playerScript.ConfigureInventory(map.Palette(), map.Inventory());
        playerScript.SetAlive(true);
        playerScript.ResetState();
    }

    /// not used in this project, kept in case arrow tiles return
    void SpawnTraps(){
        traps = [];
    }

    /// keep the camera centered on the player and inside the world
    void UpdateCamera(){
        if (player is null || map is null){
            camX = camY = 0;
            return;
        }
        auto tr = player.GetComponentAs!TransformComponent(COMPONENTS.TRANSFORM);
        if (tr is null){
            return;
        }
        float viewHeight = windowH - 80;
        float viewWidth = windowW;
        float targetX = tr.rect.x + tr.rect.w * 0.5f - viewWidth * 0.5f;
        float targetY = tr.rect.y + tr.rect.h * 0.5f - viewHeight * 0.5f;
        
        float worldWidth = cast(float)map.WorldWidth();
        float worldHeight = cast(float)map.WorldHeight();
        
        // Center camera if world is smaller than viewport
        if (worldWidth <= viewWidth){
            camX = -(viewWidth - worldWidth) * 0.5f;
        } else {
            float maxCamX = worldWidth - viewWidth;
            camX = clamp(targetX, 0.0f, maxCamX);
        }
        
        if (worldHeight <= viewHeight){
            camY = -(viewHeight - worldHeight) * 0.5f;
        } else {
            float maxCamY = worldHeight - viewHeight;
            camY = clamp(targetY, 0.0f, maxCamY);
        }
    }

    /// check death conditions and level completion
    void ProcessPlayerState(){
        if (playerScript is null || map is null){
            return;
        }
        auto surface = playerScript.Surface();
        auto rect = PlayerRect();
        if (rect.y > map.WorldHeight() + map.TileSize()){
            KillPlayer("fall");
        }
        if (surface.onLava){
            KillPlayer("lava");
        }
        if (!levelComplete && IsAdjacentToGoal(rect)){
            levelComplete = true;
        }
    }

    /// true if the player is close enough to the goal tile
    bool IsAdjacentToGoal(SDL_FRect playerRect){
        int goalTileX = map.GoalTileX();
        int goalTileY = map.GoalTileY();
        float tileSize = map.TileSize();
        
        SDL_FRect goalRect;
        goalRect.x = goalTileX * tileSize;
        goalRect.y = goalTileY * tileSize;
        goalRect.w = tileSize;
        goalRect.h = tileSize;
        
        SDL_FRect checkRect = playerRect;
        float margin = 4.0f;
        checkRect.x -= margin;
        checkRect.y -= margin;
        checkRect.w += margin * 2;
        checkRect.h += margin * 2;
        
        return rectsOverlap(checkRect, goalRect);
    }

    /// reload the current level from disk
    void ResetLevel(){
        if (levelId.length == 0){
            return;
        }
        LoadLevel(levelId);
    }

    /// put the player back at the spawn marker and clear state
    void RespawnPlayer(){
        if (map is null || player is null){
            return;
        }
        auto spawn = map.SpawnRect();
        auto tr = player.GetComponentAs!TransformComponent(COMPONENTS.TRANSFORM);
        auto rb = player.GetComponentAs!JumpComponent(COMPONENTS.JUMP);
        if (tr !is null){
            float playerWidth = 14.0f;
            float playerHeight = 30.0f;
            float playerX = spawn.x + (spawn.w - playerWidth) * 0.5f;
            float playerY = spawn.y + spawn.h - playerHeight;
            tr.rect.x = playerX;
            tr.rect.y = playerY;
            tr.rect.w = playerWidth;
            tr.rect.h = playerHeight;
        }
        if (rb !is null){
            rb.vx = rb.vy = 0;
        }
        playerAlive = true;
        respawnTimer = 0;
        levelComplete = false;
        if (playerScript !is null){
            playerScript.SetAlive(true);
            playerScript.ResetState();
        }
    }

    /// draw inventory slots, key hints, and completion text
    void DrawHUD(SDL_Renderer* renderer){
        SDL_FRect bar;
        bar.x = 0;
        bar.y = windowH - 80;
        bar.w = windowW;
        bar.h = 80;
        SDL_SetRenderDrawColor(renderer, 18, 20, 26, 240);
        SDL_RenderFillRect(renderer, &bar);
        drawText(renderer, 20, windowH - 70, levelTitle);
        if (playerScript is null){
            return;
        }
        auto palette = playerScript.Palette();
        auto counts = playerScript.InventorySnapshot();
        float startX = 20;
        float size = 28;
        foreach (i, id; palette){
            auto def = map.Tiles().GetById(id);
            if (def is null){
                continue;
            }
            SDL_FRect slot;
            slot.x = startX + i * (size + 16);
            slot.y = windowH - 40;
            slot.w = size;
            slot.h = size;
            
            if (def.texture is null && def.texturePath.length > 0 && resources !is null){
                def.texture = resources.LoadTexture(def.texturePath);
            }
            
            if (def.texture !is null){
                SDL_RenderTexture(renderer, def.texture, null, &slot);
            } else {
                SDL_SetRenderDrawColor(renderer, def.color.r, def.color.g, def.color.b, def.color.a);
                SDL_RenderFillRect(renderer, &slot);
            }
            
            if (playerScript.SelectedBlock() == id){
                SDL_Color outline; outline.r = 255; outline.g = 255; outline.b = 0; outline.a = 255;
                drawRectOutline(renderer, slot, outline);
            }
            int remaining = (id in counts) ? counts[id] : 0;
            drawText(renderer, slot.x, slot.y - 18, format("%d", remaining));
        }
        drawText(renderer, windowW - 220, windowH - 70, "[ ] TO CYCLE");
        drawText(renderer, windowW - 220, windowH - 50, "E/F TO PLACE");
        drawText(renderer, windowW - 220, windowH - 30, "Q TO RESET");
        if (levelComplete){
            SDL_Color gold; gold.r = 255; gold.g = 215; gold.b = 0; gold.a = 255;
            drawText(renderer, windowW * 0.5f - 100, windowH * 0.5f - 40, "LEVEL COMPLETE!", gold);
            drawText(renderer, windowW * 0.5f - 90, windowH * 0.5f - 10, "ESC TO CONTINUE", gold);
        }
    }

    /// try to place a block in front of the player
    void TryPlaceBlockInFront(){
        if (map is null || player is null || playerScript is null){
            return;
        }
        if (!playerAlive){
            return;
        }
        string blockId = playerScript.SelectedBlock();
        if (blockId.length == 0 || !playerScript.HasBlock(blockId)){
            return;
        }
        auto def = map.Tiles().GetById(blockId);
        if (def is null || !def.placeable){
            return;
        }
        auto tr = player.GetComponentAs!TransformComponent(COMPONENTS.TRANSFORM);
        auto rb = player.GetComponentAs!JumpComponent(COMPONENTS.JUMP);
        if (tr is null){
            return;
        }

        int facingDir = playerScript.FacingDirection();

        float playerCenterX = tr.rect.x + tr.rect.w * 0.5f;
        float playerCenterY = tr.rect.y + tr.rect.h * 0.5f;
        int playerTileX = cast(int)floor(playerCenterX / map.TileSize());
        int playerTileY = cast(int)floor(playerCenterY / map.TileSize());

        int tx = playerTileX + facingDir;
        int ty = playerTileY;
        if (!map.InBounds(tx, ty)){
            return;
        }
        auto current = map.TileAt(tx, ty);
        if (current !is null && current.solid){
            return;
        }
        if (!map.WithinPlacementRange(tx, ty, tr.rect, playerScript.PlacementRange())){
            return;
        }

        SDL_FRect tileRect;
        tileRect.x = tx * map.TileSize();
        tileRect.y = ty * map.TileSize();
        tileRect.w = map.TileSize();
        tileRect.h = map.TileSize();

        float margin = 2.0f;
        SDL_FRect playerCheck = tr.rect;
        playerCheck.x -= margin;
        playerCheck.y -= margin;
        playerCheck.w += margin * 2;
        playerCheck.h += margin * 2;
        if (rectsOverlap(playerCheck, tileRect)){
            return;
        }
        if (!playerScript.ConsumeBlock(blockId)){
            return;
        }
        map.SetTile(tx, ty, blockId);
    }

    /// simple axis aligned rectangle overlap test
    bool rectsOverlap(SDL_FRect a, SDL_FRect b){
        return !(a.x + a.w <= b.x || b.x + b.w <= a.x || 
                 a.y + a.h <= b.y || b.y + b.h <= a.y);
    }

    /// place a block based on screen position (used by editor cursor)
    void TryPlaceBlock(float sx, float sy){
        if (map is null || player is null || playerScript is null){
            return;
        }
        if (!playerAlive){
            return;
        }
        string blockId = playerScript.SelectedBlock();
        if (blockId.length == 0 || !playerScript.HasBlock(blockId)){
            return;
        }
        auto def = map.Tiles().GetById(blockId);
        if (def is null || !def.placeable){
            return;
        }
        float worldX = camX + sx;
        float worldY = camY + sy;
        int tx = cast(int)floor(worldX / map.TileSize());
        int ty = cast(int)floor(worldY / map.TileSize());
        if (!map.InBounds(tx, ty)){
            return;
        }
        auto current = map.TileAt(tx, ty);
        if (current !is null && current.solid){
            return;
        }
        auto tr = player.GetComponentAs!TransformComponent(COMPONENTS.TRANSFORM);
        if (tr is null){
            return;
        }
        if (!map.WithinPlacementRange(tx, ty, tr.rect, playerScript.PlacementRange())){
            return;
        }
        if (!playerScript.ConsumeBlock(blockId)){
            return;
        }
        map.SetTile(tx, ty, blockId);
    }

    /// draw the player sprite or fallback rectangle
    void RenderPlayer(SDL_Renderer* renderer){
        if (player is null){
            return;
        }
        auto tr = player.GetComponentAs!TransformComponent(COMPONENTS.TRANSFORM);
        if (tr is null){
            return;
        }
        SDL_FRect dstRect = tr.rect;
        
        float visualSize = 32.0f;
        float xOffset = (visualSize - dstRect.w) * 0.5f;
        float yOffset = (visualSize - dstRect.h); // Align bottom
        
        dstRect.x -= (camX + xOffset);
        dstRect.y -= (camY + yOffset);
        dstRect.w = visualSize;
        dstRect.h = visualSize;
        
        if (player.HasComponent(COMPONENTS.TEXTURE)){
            auto tex = player.GetComponentAs!TextureComponent(COMPONENTS.TEXTURE);
            if (tex is null || tex.texture is null){
                return;
            }
            SDL_FRect* srcRect = tex.useSrcRect ? &tex.srcRect : null;
            
            SDL_RenderTexture(renderer, tex.texture, srcRect, &dstRect);
        } else if (player.HasComponent(COMPONENTS.COLOR)){
            auto col = player.GetComponentAs!ColorComponent(COMPONENTS.COLOR);
            if (col !is null){
                SDL_SetRenderDrawColor(renderer, col.color.r, col.color.g, col.color.b, col.color.a);
                SDL_RenderFillRect(renderer, &dstRect);
            }
        }
    }

    /// load a texture once and reuse it by key
    SDL_Texture* RequireTexture(string key, string path){
        if (resources is null || path.length == 0){
            return null;
        }
        auto tex = resources.GetTexture(key);
        if (tex !is null){
            return tex;
        }
        return resources.LoadTexture(path, key);
    }

}

/// \class EditorScene
/// \brief simple level editor scene for building tile maps
class EditorScene : SceneBase {
private:
    TileMap map;
    string[] palette;
    int selectedIndex = 0;
    size_t levelIndex = 0;
    string savePath;
    int hoverTx = -1;
    int hoverTy = -1;
    bool leftMousePressed = false;
    bool rightMousePressed = false;
    string statusMessage = "";
    float statusTimer = 0.0f;
    float camX = 0;
    float camY = 0;

public:
    /// create an editor scene and remember the default save path
    this(ResourceManager res, int w, int h){
        super(res, w, h);
        savePath = res.EditorSavePath();
    }

    /// load either a saved custom level or the default level
    override void OnEnter(){
        if (savePath.length > 0 && exists(savePath)){
             LoadFromFile(savePath);
             statusMessage = "LOADED CUSTOM LEVEL";
             statusTimer = 2.0f;
        } else {
             string defaultFile = resources.EditorDefaultFile();
             if (defaultFile.length){
                 LoadFromFile(defaultFile);
             } else {
                 LoadFromIndex(0);
             }
             statusMessage = "EDITOR MODE";
             statusTimer = 2.0f;
        }
        camX = 0;
        camY = 0;
    }

    /// count down status message timer
    override void Update(float dt){
        if (statusTimer > 0){
            statusTimer -= dt;
            if (statusTimer <= 0){
                statusMessage = "";
            }
        }
    }

    /// handle editor keyboard shortcuts and mouse input
    override void HandleEvent(ref SDL_Event e){
        if (e.type == SDL_EVENT_KEY_DOWN){
            auto sym = e.key.key;
            if (sym >= SDLK_1 && sym <= SDLK_9){
                int idx = cast(int)sym - cast(int)SDLK_1;
                SelectSlot(idx);
            } else if (sym == SDLK_LEFTBRACKET){
                Cycle(-1);
            } else if (sym == SDLK_RIGHTBRACKET){
                Cycle(1);
            } else if (sym == SDLK_S){
                Save();
            } else if (sym == SDLK_L){
                LoadFromIndex(levelIndex + 1);
            } else if (sym == SDLK_P){
                if (hoverTx >= 0 && hoverTy >= 0) {
                    map.SetSpawn(hoverTx, hoverTy);
                    map.ClearTile(hoverTx, hoverTy);
                    statusMessage = "SPAWN SET";
                    statusTimer = 1.0f;
                }
            } else if (sym == SDLK_G){
                if (hoverTx >= 0 && hoverTy >= 0) {
                    map.SetGoal(hoverTx, hoverTy);
                    map.SetTile(hoverTx, hoverTy, "goal");
                    statusMessage = "GOAL SET";
                    statusTimer = 1.0f;
                }
            } else if (sym == SDLK_EQUALS || sym == SDLK_KP_PLUS){
                ModifyInventory(1);
            } else if (sym == SDLK_MINUS || sym == SDLK_KP_MINUS){
                ModifyInventory(-1);
            } else if (sym == SDLK_ESCAPE){
                RequestSwitch("menu");
            }
        } else if (e.type == SDL_EVENT_MOUSE_MOTION){
            float wx = e.motion.x + camX;
            float wy = e.motion.y + camY;
            if (map is null){
                hoverTx = hoverTy = -1;
            } else {
                hoverTx = cast(int)floor(wx / cast(float)map.TileSize());
                hoverTy = cast(int)floor(wy / cast(float)map.TileSize());
            }
            if (leftMousePressed){
                PaintTile(e.motion.x, e.motion.y);
            } else if (rightMousePressed){
                EraseTile(e.motion.x, e.motion.y);
            }
        } else if (e.type == SDL_EVENT_MOUSE_BUTTON_DOWN){
            if (e.button.button == SDL_BUTTON_LEFT){
                leftMousePressed = true;
                PaintTile(e.button.x, e.button.y);
            } else if (e.button.button == SDL_BUTTON_RIGHT){
                rightMousePressed = true;
                EraseTile(e.button.x, e.button.y);
            }
        } else if (e.type == SDL_EVENT_MOUSE_BUTTON_UP){
            if (e.button.button == SDL_BUTTON_LEFT){
                leftMousePressed = false;
            } else if (e.button.button == SDL_BUTTON_RIGHT){
                rightMousePressed = false;
            }
        }
    }

    override void Render(SDL_Renderer* renderer){
        SDL_SetRenderDrawColor(renderer, 18, 18, 24, 255);
        SDL_RenderClear(renderer);
        if (map is null){
            return;
        }
        
        int hudHeight = 100;
        int mapViewportH = windowH - hudHeight;
        
        float mapPixelH = cast(float)map.Height() * map.TileSize();
        float yOffset = 0;
        if (mapPixelH < mapViewportH){
            yOffset = (mapViewportH - mapPixelH) * 0.5f;
        }
        
        map.Render(renderer, camX, -yOffset, windowW, mapViewportH, true, true, true, hoverTx, hoverTy);
        
        SDL_FRect bar;
        bar.x = 0;
        bar.y = windowH - hudHeight;
        bar.w = windowW;
        bar.h = hudHeight;
        SDL_SetRenderDrawColor(renderer, 24, 28, 36, 255);
        SDL_RenderFillRect(renderer, &bar);
        
        // Instructions
        SDL_Color helpColor; helpColor.r = 150; helpColor.g = 160; helpColor.b = 180; helpColor.a = 255;
        drawText(renderer, 20, windowH - 95, "L-CLICK: PAINT | R-CLICK: ERASE | P: SPAWN | G: GOAL | S: SAVE", helpColor);
        drawText(renderer, 20, windowH - 80, "[/]: CYCLE | +/-: INVENTORY | ESC: QUIT", helpColor);

        // Palette
        float startX = 20;
        float size = 32;
        static bool debugPrinted = false;
        foreach (i, id; palette){
            auto def = map.Tiles().GetById(id);
            if (def is null){
                continue;
            }
            SDL_FRect slot;
            slot.x = startX + i * (size + 12);
            slot.y = windowH - 50; // Moved up slightly
            slot.w = size;
            slot.h = size;
            
            // Debug output (once)
            if (!debugPrinted){
                bool hasTexture = def.texture !is null;
                writeln("Rendering palette item ", id, ": texture=", cast(void*)def.texture, " hasTexture=", hasTexture, " path=", def.texturePath);
            }
            
            // Draw tile texture or color
            if (def.texture !is null){
                if (!debugPrinted){
                    writeln("  -> Drawing texture for ", id);
                }
                int result = SDL_RenderTexture(renderer, def.texture, null, &slot);
                if (result != 0){
                    import std.string : fromStringz;
                    writeln("  ERROR: SDL_RenderTexture failed: ", fromStringz(SDL_GetError()));
                }
            } else {
                if (!debugPrinted){
                    writeln("  -> Drawing color for ", id);
                }
                SDL_SetRenderDrawColor(renderer, def.color.r, def.color.g, def.color.b, def.color.a);
                SDL_RenderFillRect(renderer, &slot);
            }
            
            if (selectedIndex == cast(int)i){
                SDL_Color outline; outline.r = 255; outline.g = 255; outline.b = 0; outline.a = 255;
                drawRectOutline(renderer, slot, outline);
                
                // Show inventory count for selected below slot with spacing
                int count = map.GetInventoryCount(id);
                drawText(renderer, slot.x, slot.y + size + 2, format("x%d", count));
            }
            
            string text = id.length ? id[0 .. 1].toUpper() : "?";
            SDL_Color txtCol; txtCol.r = 0; txtCol.g = 0; txtCol.b = 0; txtCol.a = 255;
            drawText(renderer, slot.x + 6, slot.y + 6, text, txtCol);
        }
        debugPrinted = true;

        // Status Message
        if (statusMessage.length > 0){
            SDL_Color statusCol; statusCol.r = 80; statusCol.g = 255; statusCol.b = 80; statusCol.a = 255;
            // Center text roughly
            float msgX = windowW * 0.5f - (statusMessage.length * 5); 
            drawText(renderer, msgX, windowH - 65, statusMessage, statusCol);
        }
    }
private:
    /// load a level into the editor by index
    void LoadFromIndex(size_t idx){
        auto levels = resources.Levels();
        if (levels.length == 0){
            return;
        }
        levelIndex = idx % levels.length;
        auto entry = levels[levelIndex];
        LoadFromFile(entry.file);
        statusMessage = "LOADED: " ~ entry.id;
        statusTimer = 2.0f;
    }

    /// write the current level to disk and update status text
    void Save(){
        if (map is null){
            return;
        }
        
        // Validate Spawn and Goal
        if (map.SpawnTileX() == map.GoalTileX() && map.SpawnTileY() == map.GoalTileY()){
            statusMessage = "ERROR: SPAWN == GOAL";
            statusTimer = 3.0f;
            return;
        }

        if (savePath.length == 0){
            savePath = "Game/Scenes/custom_level.json";
        }
        
        // Ensure title is set correctly for custom levels
        if (map.Title() == "Molten Climb" || map.Title().length == 0){
            map.SetTitle("Custom Level");
        }
        
        if (map.Save(savePath)){
            statusMessage = "SAVED TO " ~ savePath;
        } else {
            statusMessage = "SAVE FAILED";
        }
        statusTimer = 3.0f;
    }

    /// choose a palette index from number keys
    void SelectSlot(int idx){
        if (palette.length == 0){
            return;
        }
        if (idx < 0) idx = 0;
        if (idx >= cast(int)palette.length) idx = cast(int)palette.length - 1;
        selectedIndex = idx;
    }

    /// move palette selection forward or backward
    void Cycle(int delta){
        if (palette.length == 0){
            return;
        }
        selectedIndex = (selectedIndex + delta) % cast(int)palette.length;
        if (selectedIndex < 0){
            selectedIndex = cast(int)palette.length - 1;
        }
    }

    /// change inventory count for the selected tile id
    void ModifyInventory(int delta){
        if (map is null || palette.length == 0) return;
        string id = palette[selectedIndex];
        int current = map.GetInventoryCount(id);
        map.SetInventoryCount(id, current + delta);
    }

    /// set a tile at the given screen position
    void PaintTile(float sx, float sy){
        if (map is null || palette.length == 0){
            return;
        }

        int hudHeight = 100;
        int mapViewportH = windowH - hudHeight;
        float mapPixelH = cast(float)map.Height() * map.TileSize();
        float yOffset = 0;
        if (mapPixelH < mapViewportH){
            yOffset = (mapViewportH - mapPixelH) * 0.5f;
        }
        
        float wx = sx;
        float wy = sy - yOffset;
        
        int tx = cast(int)floor(wx / map.TileSize());
        int ty = cast(int)floor(wy / map.TileSize());
        if (!map.InBounds(tx, ty)){
            return;
        }
        string id = palette[selectedIndex];
        map.SetTile(tx, ty, id);
    }

    /// clear the tile at the given screen position
    void EraseTile(float sx, float sy){
        if (map is null){
            return;
        }
        
        int hudHeight = 100;
        int mapViewportH = windowH - hudHeight;
        float mapPixelH = cast(float)map.Height() * map.TileSize();
        float yOffset = 0;
        if (mapPixelH < mapViewportH){
            yOffset = (mapViewportH - mapPixelH) * 0.5f;
        }

        float wx = sx;
        float wy = sy - yOffset;

        int tx = cast(int)floor(wx / map.TileSize());
        int ty = cast(int)floor(wy / map.TileSize());
        map.ClearTile(tx, ty);
    }

    /// load a map file into the editor and ensure textures are ready
    void LoadFromFile(string file){
        auto tileSet = resources.Tiles();
        if (tileSet is null || file.length == 0){
            return;
        }
        auto json = resources.LoadLevelJSON(file);
        if (json.type == JSONType.null_){
            return;
        }
        map = new TileMap(tileSet);
        map.SetTextureLoader((path){
            if (resources is null || path.length == 0){
                return cast(SDL_Texture*)null;
            }
            return resources.LoadTexture(path);
        });
        map.LoadFromJSON(json);
        
        foreach(id; tileSet.AllTileIds()){
            auto def = tileSet.GetById(id);
            if (def !is null && def.texturePath.length > 0){
                if (def.texture is null){
                    writeln("Loading texture for ", id, ": ", def.texturePath);
                    def.texture = resources.LoadTexture(def.texturePath);
                    if (def.texture is null){
                        writeln("  FAILED to load texture");
                    } else {
                        writeln("  SUCCESS - texture loaded at ", cast(void*)def.texture);
                    }
                } else {
                    writeln("Texture already loaded for ", id, " at ", cast(void*)def.texture);
                }
            }
        }
        
        BuildPalette();
        selectedIndex = 0;
    }

    /// build the editor palette from all tile ids, skipping special ones
    void BuildPalette(){
        auto tileSet = resources.Tiles();
        if (tileSet is null){
            palette = [];
            return;
        }
        palette = [];
        foreach(id; tileSet.AllTileIds()){
            if (id == "empty" || id == "goal" || id == "spawn" || 
                id == "arrow_right" || id == "arrow_left"){
                continue;
            }
            palette ~= id;
        }
    }
}

private SDL_Color makeColor(ubyte r, ubyte g, ubyte b, ubyte a = 255){
    /// build an SDL_Color from components
    SDL_Color c;
    c.r = r;
    c.g = g;
    c.b = b;
    c.a = a;
    return c;
}

/// draw a thin outline around a rectangle
private void drawRectOutline(SDL_Renderer* renderer, SDL_FRect rect, SDL_Color color){
    SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
    SDL_FRect top = rect;
    top.h = 2;
    SDL_RenderFillRect(renderer, &top);
    SDL_FRect bottom = rect;
    bottom.y = rect.y + rect.h - 2;
    bottom.h = 2;
    SDL_RenderFillRect(renderer, &bottom);
    SDL_FRect left = rect;
    left.w = 2;
    SDL_RenderFillRect(renderer, &left);
    SDL_FRect right = rect;
    right.x = rect.x + rect.w - 2;
    right.w = 2;
    SDL_RenderFillRect(renderer, &right);
}

/// draw white debug text at a position
private void drawText(SDL_Renderer* renderer, float x, float y, string text){
    SDL_Color c;
    c.r = 255; c.g = 255; c.b = 255; c.a = 255;
    drawText(renderer, x, y, text, c);
}

/// draw debug text at a position with a custom color
private void drawText(SDL_Renderer* renderer, float x, float y, string text, SDL_Color color){
    if (renderer is null || text.length == 0){
        return;
    }
    SDL_SetRenderDrawColor(renderer, color.r, color.g, color.b, color.a);
    SDL_RenderDebugText(renderer, cast(int)x, cast(int)y, text.toStringz);
}

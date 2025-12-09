/**
 * @file scripts.d
 * @brief gameplay scripts that use the ecs data
 *
 * holds player movement and helper types shared with scenes.
 */
module scripts;

import std.math;
import bindbc.sdl;

import component;
import gameobject;
import tilemap;

/// \struct MovementResult
/// \brief result of moving the player against the tile map
struct MovementResult {
    bool grounded = false;
    SurfaceInfo surface;
}

/// \interface IPlayerWorld
/// \brief small interface used by player script to talk to the world
interface IPlayerWorld {
    /// move the player body in the world and report collisions
    MovementResult ResolvePlayerMovement(GameObject player, JumpComponent body, float dt);
}

/// \class ScriptBase
/// \brief simple script base with shared owner/context
class ScriptBase : IScript {
protected:
    Object context;
    GameObject owner;
public:
    /// remember owner and context when added to a gameobject
    override void OnAttach(GameObject o, Object ctx){
        owner = o;
        context = ctx;
    }
    /// default input hook does nothing
    override void Input(GameObject){}
    /// default update hook does nothing
    override void Update(float, GameObject){}
}

/// \class PlayerScript
/// \brief player movement, jumping, and animation logic
class PlayerScript : ScriptBase {
private:
    IPlayerWorld world;
    SurfaceInfo lastSurface;
    MovementResult lastMove;
    float moveSpeed = 180.0f;
    float airControl = 0.85f;
    float jumpForce = 420.0f;
    float gravity = 960.0f;
    float maxFall = 960.0f;
    float coyoteTime = 0.12f;
    float coyoteTimer = 0;

    bool jumpHeld = false;
    bool grounded = false;
    string[] palette;

    int selectedIndex = 0;
    int[string] inventory;
    int placementRange = 4;

    bool alive = true;
    float lastMoveInput = 0;
    int facingDir = 1;
public:
    /// save world reference and call base attach
    override void OnAttach(GameObject o, Object ctx){
        super.OnAttach(o, ctx);
        world = cast(IPlayerWorld)ctx;
    }

    /// read input, integrate movement, and update animation state
    override void Update(float dt, GameObject o){
        if (!alive || world is null){
            return;
        }
        auto rb = o.GetComponentAs!JumpComponent(COMPONENTS.JUMP);
        if (rb is null){
            return;
        }
        const bool* keys = SDL_GetKeyboardState(null);
        float moveInput = 0;
        if (keys[SDL_SCANCODE_A] || keys[SDL_SCANCODE_LEFT]) moveInput -= 1;
        if (keys[SDL_SCANCODE_D] || keys[SDL_SCANCODE_RIGHT]) moveInput += 1;
        lastMoveInput = moveInput;  // Save for animation
        if (moveInput != 0){
            facingDir = moveInput > 0 ? 1 : -1;
        }
        float speedModifier = lastSurface.onMud ? 0.55f : (lastSurface.onSecret ? 1.5f : 1.0f);
        float applied = moveInput * moveSpeed * speedModifier;
        if (!grounded){
            applied *= airControl;
        }
        rb.vx = applied;

        bool wantsJump = keys[SDL_SCANCODE_SPACE] || keys[SDL_SCANCODE_W] || keys[SDL_SCANCODE_UP];
        float jumpBoost = lastSurface.onRubber ? 1.35f : 1.0f;
        if (wantsJump && !jumpHeld && (grounded || coyoteTimer > 0)){
            rb.vy = -(jumpForce * jumpBoost);
            grounded = false;
            coyoteTimer = 0;
            jumpHeld = true;
        }
        if (!wantsJump){
            jumpHeld = false;
        }

        rb.vy += gravity * dt;
        if (rb.vy > maxFall){
            rb.vy = maxFall;
        }

        lastMove = world.ResolvePlayerMovement(o, rb, dt);
        grounded = lastMove.grounded;
        if (grounded){
            coyoteTimer = coyoteTime;
        } else if (coyoteTimer > 0){
            coyoteTimer -= dt;
            if (coyoteTimer < 0) coyoteTimer = 0;
        }
        lastSurface = lastMove.surface;
        
        UpdateAnimations(o);
    }
    
    /// choose animation based on move direction and grounded state
    void UpdateAnimations(GameObject o){
        if (!o.HasComponent(COMPONENTS.ANIMATION)){
            return;
        }
        auto anim = o.GetComponentAs!AnimationComponent(COMPONENTS.ANIMATION);
        if (anim is null){
            return;
        }
        auto rb = o.GetComponentAs!JumpComponent(COMPONENTS.JUMP);
        if (rb is null){
            return;
        }
        
        bool facingRight = (facingDir > 0);
        
        if (!grounded){
            if (rb.vy < 0){
                anim.PlayAnimation(facingRight ? "jump_right" : "jump_left");
            } else {
                anim.PlayAnimation(facingRight ? "fall_right" : "fall_left");
            }
        } else {
            if (lastMoveInput > 0){
                anim.PlayAnimation("walk_right");
            } else if (lastMoveInput < 0){
                anim.PlayAnimation("walk_left");
            } else {
                anim.PlayAnimation(facingRight ? "idle_right" : "idle_left");
            }
        }
    }

    /// set up build palette and starting counts
    void ConfigureInventory(string[] order, int[string] counts){
        palette = order.dup;
        inventory = counts.dup;
        if (palette.length == 0){
            palette ~= "dirt";
        }
        foreach (id; palette){
            if (!(id in inventory)){
                inventory[id] = 0;
            }
        }
        selectedIndex = 0;
    }

    /// get a copy of the current palette order
    string[] Palette(){
        return palette.dup;
    }

    /// get a copy of the current inventory counts
    int[string] InventorySnapshot(){
        return inventory.dup;
    }

    /// select a palette slot by index
    bool SelectSlot(int idx){
        if (palette.length == 0){
            return false;
        }
        if (idx < 0){
            idx = 0;
        }
        if (idx >= cast(int)palette.length){
            idx = cast(int)palette.length - 1;
        }
        selectedIndex = idx;
        return true;
    }

    /// move the selection forward or backward
    void CycleSelection(int delta){
        if (palette.length == 0){
            return;
        }
        selectedIndex = (selectedIndex + delta) % cast(int)palette.length;
        if (selectedIndex < 0){
            selectedIndex = cast(int)palette.length - 1;
        }
    }

    /// id of the currently selected tile or empty string
    string SelectedBlock(){
        if (palette.length == 0){
            return "";
        }
        return palette[cast(size_t)selectedIndex];
    }

    /// true if the player owns at least one of the given tile
    bool HasBlock(string id){
        if (id in inventory){
            return inventory[id] > 0;
        }
        return false;
    }

    /// spend one tile from inventory if available
    bool ConsumeBlock(string id){
        if (!HasBlock(id)){
            return false;
        }
        inventory[id] -= 1;
        return true;
    }

    /// give back a tile to the inventory
    void ReturnBlock(string id){
        inventory[id] += 1;
    }

    /// placement distance in tiles from the player
    int PlacementRange(){
        return placementRange;
    }

    /// 1 for right, -1 for left
    int FacingDirection(){
        return facingDir;
    }

    /// true if the player is on the ground
    bool IsGrounded(){
        return grounded;
    }

    /// last sampled surface info under the player
    SurfaceInfo Surface(){
        return lastSurface;
    }

    /// enable or disable player input and movement
    void SetAlive(bool value){
        alive = value;
    }

    /// clear internal timers and contact info
    void ResetState(){
        grounded = false;
        coyoteTimer = 0;
        jumpHeld = false;
        lastSurface = SurfaceInfo();
        lastMove = MovementResult();
    }
}

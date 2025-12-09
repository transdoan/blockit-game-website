/**
 * @file component.d
 * @brief small component types used by game objects
 *
 * holds data for position, drawing, physics, and simple state.
 */
module component;

import std.json;
import bindbc.sdl;

/// ids used to look up components on a game object
enum COMPONENTS {TRANSFORM, TEXTURE, ANIMATION, JUMP, COLOR}

/// base interface so all components can be stored together
interface IComponent {}

/// \class TransformComponent
/// \brief rectangle in world space
class TransformComponent : IComponent {
    SDL_FRect rect;
    /// store position and size
    this (float x, float y, float w, float h){
        rect.x = x; 
        rect.y = y; 
        rect.w = w; 
        rect.h = h; 
    }
}

/// \class TextureComponent
/// \brief texture handle and optional source rect
class TextureComponent : IComponent {
    SDL_Texture* texture;
    SDL_FRect srcRect; 
    bool useSrcRect = false;

    /// use the full texture
    this (SDL_Texture* tex){
        texture = tex; 
        srcRect = SDL_FRect(0, 0, 0, 0);
    }

    /// use only a tile from a sprite sheet
    this (SDL_Texture* tex, float w, float h){
        texture = tex; 
        srcRect = SDL_FRect(0, 0, w, h);
        useSrcRect = true;
    }
}

/// \class AnimationComponent
/// \brief simple sprite animation player
class AnimationComponent : IComponent {
    struct Frame {
        SDL_Rect rect;
        float elapsedTime;
    }

    Frame[] frames; 
    long[][string] frameSequences; 
    string currentAnimation; 
    long currentFrame = 0; 
    long lastFrameInSequence = 0; 
    float animationTimer = 0; 
    float frameTime = 0.2f;
    bool isPlaying = false;

    /// build frames and sequences from json
    this (JSONValue animationData){
        LoadFromJSON(animationData);
    }

    /// read format and frame list from json
    void LoadFromJSON(JSONValue animationData){
        if (animationData.type == JSONType.null_){
            return;
        }
        JSONValue format = animationData["format"];
        long width = format["width"].integer; 
        long height = format["height"].integer; 
        long tileWidth = format["tileWidth"].integer; 
        long tileHeight = format["tileHeight"].integer;
        long columns = width / tileWidth; long rows = height / tileHeight;

        for (long row = 0; row < rows; row++){
            for (long col = 0; col < columns; col++){
                Frame f; f.rect.x = cast(int)(col * tileWidth); 
                f.rect.y = cast(int)(row * tileHeight); 
                f.rect.w = cast(int)tileWidth; 
                f.rect.h = cast(int)tileHeight; 
                frames ~= f; 
            }
        }

        if ("frames" in animationData){
            foreach (string animName, JSONValue indices; animationData["frames"].object){
                long[] seq; 
                foreach (JSONValue idx; indices.array){
                    seq ~= idx.integer; 
                }
                frameSequences[animName] = seq;
            }
        }
    }

    /// start or restart an animation by name
    void PlayAnimation(string name){
        if (name !in frameSequences){
            return;
        }
        if (currentAnimation != name){
            currentAnimation = name;
            currentFrame = 0;
            animationTimer = 0;
            lastFrameInSequence = frameSequences[name].length - 1;
        } 
        isPlaying = true;
    }
    
    /// set the first frame on a texture before updates run
    void SetInitialFrame(ref TextureComponent tex){
        if (currentAnimation.length == 0 || currentAnimation !in frameSequences){
            return;
        }
        if (frames.length == 0){
            return;
        }
        auto seq = frameSequences[currentAnimation];
        if (seq.length == 0){
            return;
        }
        auto frame = frames[cast(size_t)seq[0]];
        tex.srcRect.x = frame.rect.x;
        tex.srcRect.y = frame.rect.y;
        tex.srcRect.w = frame.rect.w;
        tex.srcRect.h = frame.rect.h;
        tex.useSrcRect = true;
    }

    /// advance animation over time and write src rect into texture
    void Update(float dt, ref TextureComponent tex){
        if (!isPlaying || currentAnimation !in frameSequences){
            return;
        }
        animationTimer += dt;
        if (animationTimer >= frameTime){
            animationTimer = 0;
            currentFrame++; 
            if(currentFrame > lastFrameInSequence) {
                currentFrame = 0; 
            }
        }
        auto seq = frameSequences[currentAnimation];
        auto frame = frames[cast(size_t)seq[cast(size_t)currentFrame]]; 
        tex.srcRect.x = frame.rect.x;
        tex.srcRect.y = frame.rect.y;
        tex.srcRect.w = frame.rect.w;
        tex.srcRect.h = frame.rect.h;
        tex.useSrcRect = true;
    }
}

/// \class JumpComponent
/// \brief velocity and state used for jumping and gravity
class JumpComponent : IComponent {
    float vx = 0;
    float vy = 0;
    float ax = 0;
    float ay = 0;
    float damping = 0.995f;
    bool grounded = false;
}

/// \class ColorComponent
/// \brief solid color for drawing rectangles
class ColorComponent : IComponent {
    SDL_Color color;
    /// store a color from components
    this(ubyte r, ubyte g, ubyte b, ubyte a = 255){
        color = SDL_Color(r, g, b, a);
    }
    /// store an existing sdl color
    this(SDL_Color c){
        color = c;
    }
}

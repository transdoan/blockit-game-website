/**
 * @file gameobject.d
 * @brief simple entity type built from components and scripts
 *
 * each gameobject stores a set of components and runs scripts every frame.
 */
module gameobject;

import component;
import bindbc.sdl;

/// \interface IScript
/// \brief behavior that can be attached to a gameobject
interface IScript { 
    /// called once when the script is added
    void OnAttach(GameObject owner, Object app);
    /// handle input for this frame
    void Input(GameObject owner);
    /// update logic for this frame
    void Update(float dt, GameObject owner);
}

/// \class GameObject
/// \brief basic entity that owns components and scripts
class GameObject {
    string tag;
    bool alive = true;
    IComponent[COMPONENTS] components; 
    IScript[] scripts;

    /// store or replace a component by type
    void AddComponent(COMPONENTS t, IComponent c){
        components[t] = c;
    }

    /// get a component as the base interface
    IComponent GetComponent(COMPONENTS t){
        if (t in components){
            return components[t];
        }
        return null;
    }

    /// get a component as a concrete type
    T GetComponentAs(T)(COMPONENTS t){
        if (t in components){
            return cast(T)components[t];
        }
        return null;
    }

    /// true if a component of the given type exists
    bool HasComponent(COMPONENTS t){
        return (t in components) !is null;
    }
    
    /// attach a script and call its OnAttach hook
    void AddScript(IScript s, Object app){
        scripts ~= s;
        s.OnAttach(this, app);
    }

    /// forward input to all scripts
    void Input(){
        foreach (s; scripts){
            s.Input(this);
        }
    }
    /// update scripts and built in animation / rotation
    void Update(float dt){
        foreach (s; scripts){
            s.Update(dt, this);
            if (HasComponent(COMPONENTS.ANIMATION) && HasComponent(COMPONENTS.TEXTURE)){
                auto a = GetComponentAs!AnimationComponent(COMPONENTS.ANIMATION);
                auto t = GetComponentAs!TextureComponent(COMPONENTS.TEXTURE);
                if (a !is null && t !is null){
                    a.Update(dt, t);
                }
            }
        }
    }
    /// draw the object using either texture or solid color
    void Render(SDL_Renderer* renderer, float camX, float camY){
        if (!HasComponent(COMPONENTS.TRANSFORM)){
            return;
        }
        auto tr = GetComponentAs!TransformComponent(COMPONENTS.TRANSFORM);
        if (tr is null){
            return;
        }
        SDL_FRect dstRect = tr.rect;
        dstRect.x -= camX;
        dstRect.y -= camY;
        if (HasComponent(COMPONENTS.TEXTURE)){
            auto tex = GetComponentAs!TextureComponent(COMPONENTS.TEXTURE);
            if (tex is null || tex.texture is null){
                return;
            }
            SDL_FRect* srcRect = tex.useSrcRect ? &tex.srcRect : null;
            SDL_RenderTexture(renderer, tex.texture, srcRect, &dstRect);
            return;
        }
        if (HasComponent(COMPONENTS.COLOR)){
            auto col = GetComponentAs!ColorComponent(COMPONENTS.COLOR);
            if (col is null){
                return;
            }
            SDL_SetRenderDrawColor(renderer, col.color.r, col.color.g, col.color.b, col.color.a);
            SDL_RenderFillRect(renderer, &dstRect);
        }
    }
}

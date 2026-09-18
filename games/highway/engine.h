#ifndef HIGHWAY_ENGINE_H
#define HIGHWAY_ENGINE_H
#include "apple3.h"
extern uint8_t page, scene, road_phase, road_pose, engine_pitch, engine_on;
extern uint8_t object_id, object_x, object_y, object_w, object_h;
extern uint8_t geom[392], road_damage[56], object_slot, object_full;
extern const uint8_t asset_w[132], asset_h[132];
void road_prepare(void);
uint8_t object_damaged(void);
void object_damage(void);
void __fastcall__ digit_draw(uint8_t digit);
void engine_init(void);
void scene_init(void);
void road_load(void);
void road_draw(void);
void object_draw(void);
void object_erase(void);
void present(void);
void say_ready(void);
uint16_t clock_read(void);
void __fastcall__ text(const char *s);
#endif

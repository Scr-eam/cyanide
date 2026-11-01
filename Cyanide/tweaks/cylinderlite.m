//
//  cylinderlite.m
//  Cyanide
//

#import "cylinderlite.h"
#import "remote_objc.h"
#import "sb_walk.h"
#import "../LogTextView.h"

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <float.h>
#import <math.h>
#import <stdio.h>
#import <string.h>

typedef struct { double x, y; } CLPoint;
typedef struct { double width, height; } CLSize;
typedef struct { double x, y, width, height; } CLRect;
typedef struct { double a, b, c, d, tx, ty; } CLTransform;

static bool s_cylinderlite_active = false;
static CylinderLiteEffect s_cylinderlite_effect = CylinderLiteEffectZoomFadeOut;
static int s_cylinderlite_intensity_pct = 100;
static int s_cylinderlite_opacity_pct = 100;
static bool s_cylinderlite_follow_gesture = true;
static int s_cylinderlite_one_shot_duration_ms = 520;
static int s_cylinderlite_last_page = -9999;
static uint64_t s_cylinderlite_last_list = 0;
static uint64_t s_cylinderlite_scroll = 0;
static uint64_t s_cylinderlite_pan = 0;
static uint64_t s_cylinderlite_lists[16] = {0};
static double s_cylinderlite_list_x[16] = {0};
static int s_cylinderlite_list_count = 0;
static double s_cylinderlite_page_width = 0.0;
static uint64_t s_cylinderlite_enter_animations[2] = {0};
static uint64_t s_cylinderlite_exit_animations[2] = {0};
static uint64_t s_cylinderlite_animation_key = 0;
static bool s_cylinderlite_gesture_animating = false;
static int s_cylinderlite_gesture_from_page = -1;
static int s_cylinderlite_gesture_to_page = -1;
static bool s_cylinderlite_finish_animating = false;
static int s_cylinderlite_finish_from_page = -1;
static int s_cylinderlite_finish_to_page = -1;
static double s_cylinderlite_finish_progress = 0.0;
static double s_cylinderlite_finish_target = 0.0;
static unsigned int s_cylinderlite_idle_ticks = 0;
static uint64_t s_cylinderlite_one_shot_cleanup_from_list = 0;
static uint64_t s_cylinderlite_one_shot_cleanup_to_list = 0;
static unsigned int s_cylinderlite_one_shot_cleanup_ticks = 0;

// Retained only while a live session exists. Geometry is captured before effects
// are applied; transformed frames must never be used to calculate swipe progress.
typedef struct {
    uint64_t layer;
    uint64_t setters[3]; // position, transform, opacity; reused for the whole session
    CATransform3D transform;
    CLPoint position;
    double opacity, width, height;
    bool modified;
} CLPageVisual;
static CLPageVisual s_page_visuals[16];
static double s_last_offset = NAN;
static double s_perspective_distance = 0;

typedef struct {
    CLPoint position;
    CATransform3D transform;
    float opacity;
} CLFrameValues;
static CLFrameValues s_frame_values[16];
static uint64_t s_frame_memory, s_frame_batch, s_offset_invocation;
static uint64_t s_transaction_begin, s_transaction_disable, s_transaction_commit;
static uint32_t s_batch_mask;
static bool s_write_position;
static unsigned int s_frame_count;
static double s_frame_total_ms, s_frame_max_ms;

static void cl_restore_follow_pages(void);

static NSString * const kCylinderLiteAnimationKey = @"com.darksword.cylinderlite.page";

static int cl_clamp_int(int value, int minValue, int maxValue)
{
    if (value < minValue) return minValue;
    if (value > maxValue) return maxValue;
    return value;
}

static double cl_fraction_from_pct(int pct, double minValue, double maxValue)
{
    double value = (double)cl_clamp_int(pct, 0, 100) / 100.0;
    if (value < minValue) value = minValue;
    if (value > maxValue) value = maxValue;
    return value;
}

static uint64_t cl_safe_msg(uint64_t object, const char *selector,
                            uint64_t a0, uint64_t a1, uint64_t a2, uint64_t a3)
{
    if (!r_is_objc_ptr(object) || !selector || !r_responds_main(object, selector)) return 0;
    return r_msg2_main(object, selector, a0, a1, a2, a3);
}

static bool cl_get_point(uint64_t object, const char *selector, CLPoint *out)
{
    if (!r_is_objc_ptr(object) || !selector || !out ||
        !r_responds_main(object, selector)) return false;
    memset(out, 0, sizeof(*out));
    return r_msg2_main_struct_ret(object, selector, out, sizeof(*out),
                                  NULL, 0, NULL, 0, NULL, 0, NULL, 0);
}

static bool cl_get_point_fast(uint64_t object, const char *selector, CLPoint *out)
{
    if (!object || !selector || !out) return false;
    memset(out, 0, sizeof(*out));
    return r_msg2_main_struct_ret(object, selector, out, sizeof(*out),
                                  NULL, 0, NULL, 0, NULL, 0, NULL, 0);
}

static bool cl_get_size(uint64_t object, const char *selector, CLSize *out)
{
    if (!r_is_objc_ptr(object) || !selector || !out ||
        !r_responds_main(object, selector)) return false;
    memset(out, 0, sizeof(*out));
    return r_msg2_main_struct_ret(object, selector, out, sizeof(*out),
                                  NULL, 0, NULL, 0, NULL, 0, NULL, 0);
}

static bool cl_get_rect(uint64_t object, const char *selector, CLRect *out)
{
    if (!r_is_objc_ptr(object) || !selector || !out ||
        !r_responds_main(object, selector)) return false;
    memset(out, 0, sizeof(*out));
    return r_msg2_main_struct_ret(object, selector, out, sizeof(*out),
                                  NULL, 0, NULL, 0, NULL, 0, NULL, 0);
}

static bool cl_get_bool(uint64_t object, const char *selector)
{
    if (!r_is_objc_ptr(object) || !selector ||
        !r_responds_main(object, selector)) return false;
    return r_msg2_main(object, selector, 0, 0, 0, 0) != 0;
}

static uint64_t cl_nsnumber_double(double value)
{
    uint64_t numberClass = r_class("NSNumber");
    if (!r_is_objc_ptr(numberClass)) return 0;
    return r_msg2_main_raw(numberClass, "numberWithDouble:",
                           &value, sizeof(value),
                           NULL, 0, NULL, 0, NULL, 0);
}

static uint64_t cl_basic_animation(const char *keyPath,
                                   double fromValue,
                                   double toValue,
                                   double duration)
{
    uint64_t animationClass = r_class("CABasicAnimation");
    if (!r_is_objc_ptr(animationClass)) return 0;

    uint64_t keyPathString = r_nsstr_retained(keyPath);
    if (!r_is_objc_ptr(keyPathString)) return 0;
    uint64_t animation = r_msg2_main(animationClass, "animationWithKeyPath:",
                                     keyPathString, 0, 0, 0);
    r_msg2(keyPathString, "release", 0, 0, 0, 0);
    if (!r_is_objc_ptr(animation)) return 0;

    uint64_t fromNumber = cl_nsnumber_double(fromValue);
    uint64_t toNumber = cl_nsnumber_double(toValue);
    if (r_is_objc_ptr(fromNumber)) r_msg2_main(animation, "setFromValue:", fromNumber, 0, 0, 0);
    if (r_is_objc_ptr(toNumber)) r_msg2_main(animation, "setToValue:", toNumber, 0, 0, 0);
    r_msg2_main_raw(animation, "setDuration:",
                    &duration, sizeof(duration),
                    NULL, 0, NULL, 0, NULL, 0);
    return animation;
}

static void cl_add_basic_animation(uint64_t animations,
                                   const char *keyPath,
                                   double fromValue,
                                   double toValue,
                                   double duration)
{
    if (!r_is_objc_ptr(animations) || !keyPath) return;
    uint64_t animation = cl_basic_animation(keyPath, fromValue, toValue, duration);
    if (r_is_objc_ptr(animation)) r_msg2_main(animations, "addObject:", animation, 0, 0, 0);
}

static void cl_add_effect_animation(uint64_t animations,
                                    const char *keyPath,
                                    double amount,
                                    double duration,
                                    bool entering)
{
    if (entering) {
        cl_add_basic_animation(animations, keyPath, amount, 0.0, duration);
    } else {
        cl_add_basic_animation(animations, keyPath, 0.0, -amount, duration);
    }
}

static void cl_add_opacity_animation(uint64_t animations,
                                     double minOpacity,
                                     double duration,
                                     bool entering)
{
    cl_add_basic_animation(animations, "opacity",
                           entering ? minOpacity : 1.0,
                           entering ? 1.0 : minOpacity,
                           duration);
}

static bool cl_effect_uses_scale_controls(CylinderLiteEffect effect)
{
    return effect == CylinderLiteEffectZoomFadeOut ||
           effect == CylinderLiteEffectZoomFadeIn;
}

static bool cl_effect_uses_opacity_controls(CylinderLiteEffect effect)
{
    switch (effect) {
        case CylinderLiteEffectSlide:
        case CylinderLiteEffectFlip:
        case CylinderLiteEffectVerticalScroll:
        case CylinderLiteEffectCubeOutside:
        case CylinderLiteEffectCardHorizontal:
        case CylinderLiteEffectHinge:
        case CylinderLiteEffectZoomFadeOut:
        case CylinderLiteEffectZoomFadeIn:
            return true;
        default:
            return false;
    }
}

static uint64_t cl_build_page_animation(CylinderLiteEffect effect,
                                        int direction,
                                        bool entering)
{
    uint64_t animationGroupClass = r_class("CAAnimationGroup");
    uint64_t arrayClass = r_class("NSMutableArray");
    if (!r_is_objc_ptr(animationGroupClass) || !r_is_objc_ptr(arrayClass)) return 0;

    uint64_t group = r_msg2_main(animationGroupClass, "animation", 0, 0, 0, 0);
    uint64_t animations = r_msg2_main(arrayClass, "array", 0, 0, 0, 0);
    if (!r_is_objc_ptr(group) || !r_is_objc_ptr(animations)) return 0;

    bool usesScaleControls = cl_effect_uses_scale_controls(effect);
    double minScale = usesScaleControls
        ? cl_fraction_from_pct(s_cylinderlite_intensity_pct, 0.70, 1.0)
        : 0.80;
    double minOpacity = cl_effect_uses_opacity_controls(effect)
        ? cl_fraction_from_pct(s_cylinderlite_opacity_pct, 0.10, 1.0)
        : 0.35;
    double scaleDrop = 1.0 - minScale;
    double effectAmount = usesScaleControls
        ? (scaleDrop / 0.20)
        : ((double)cl_clamp_int(s_cylinderlite_intensity_pct, 70, 100) / 90.0);
    if (effectAmount < 0.05) effectAmount = 0.05;
    if (effectAmount > 1.50) effectAmount = 1.50;
    double duration = s_cylinderlite_follow_gesture
        ? 0.32
        : ((double)s_cylinderlite_one_shot_duration_ms / 1000.0);
    double width = s_cylinderlite_page_width > 1.0 ? s_cylinderlite_page_width : 428.0;
    double height = width * 1.90;
    double dir = direction < 0 ? -1.0 : 1.0;
    double pi = 3.14159265358979323846;

    switch (effect) {
        case CylinderLiteEffectSlide:
            cl_add_effect_animation(animations, "transform.translation.x",
                                    dir * 54.0 * effectAmount, duration, entering);
            cl_add_opacity_animation(animations, minOpacity, duration, entering);
            break;
        case CylinderLiteEffectFlip:
            cl_add_effect_animation(animations, "transform.rotation.y",
                                    dir * 0.72 * effectAmount, duration, entering);
            cl_add_opacity_animation(animations, minOpacity, duration, entering);
            break;
        case CylinderLiteEffectPageSpin:
            cl_add_effect_animation(animations, "transform.rotation.z",
                                    dir * pi * 2.0 * effectAmount, duration, entering);
            break;
        case CylinderLiteEffectPageFlip:
            cl_add_effect_animation(animations, "transform.rotation.y",
                                    dir * pi * effectAmount, duration, entering);
            break;
        case CylinderLiteEffectPageTwist:
            cl_add_effect_animation(animations, "transform.rotation.x",
                                    -dir * pi * 0.72 * effectAmount, duration, entering);
            break;
        case CylinderLiteEffectVerticalScroll:
            cl_add_effect_animation(animations, "transform.translation.y",
                                    -dir * height * 0.42 * effectAmount, duration, entering);
            cl_add_opacity_animation(animations, minOpacity, duration, entering);
            break;
        case CylinderLiteEffectBackwards:
            cl_add_effect_animation(animations, "transform.translation.x",
                                    dir * width * 0.72 * effectAmount, duration, entering);
            break;
        case CylinderLiteEffectHellaFar:
            cl_add_effect_animation(animations, "transform.translation.x",
                                    -dir * width * 0.90 * effectAmount, duration, entering);
            break;
        case CylinderLiteEffectCubeInside:
            cl_add_effect_animation(animations, "transform.translation.x",
                                    dir * width * 0.28 * effectAmount, duration, entering);
            cl_add_effect_animation(animations, "transform.translation.z",
                                    width * 0.16 * effectAmount, duration, entering);
            cl_add_effect_animation(animations, "transform.rotation.y",
                                    -dir * pi * 0.50 * effectAmount, duration, entering);
            break;
        case CylinderLiteEffectCubeOutside:
            cl_add_effect_animation(animations, "transform.translation.x",
                                    -dir * width * 0.28 * effectAmount, duration, entering);
            cl_add_effect_animation(animations, "transform.translation.z",
                                    -width * 0.16 * effectAmount, duration, entering);
            cl_add_effect_animation(animations, "transform.rotation.y",
                                    dir * pi * 0.50 * effectAmount, duration, entering);
            cl_add_opacity_animation(animations, minOpacity, duration, entering);
            break;
        case CylinderLiteEffectCardHorizontal:
            cl_add_effect_animation(animations, "transform.rotation.y",
                                    dir * pi * effectAmount, duration, entering);
            cl_add_opacity_animation(animations, minOpacity, duration, entering);
            break;
        case CylinderLiteEffectCardVertical:
            cl_add_effect_animation(animations, "transform.rotation.x",
                                    -dir * pi * effectAmount, duration, entering);
            break;
        case CylinderLiteEffectWheel:
            cl_add_effect_animation(animations, "transform.translation.y",
                                    height * 0.38 * effectAmount, duration, entering);
            cl_add_effect_animation(animations, "transform.rotation.z",
                                    -dir * pi * 0.35 * effectAmount, duration, entering);
            break;
        case CylinderLiteEffectHinge:
            cl_add_effect_animation(animations, "transform.translation.x",
                                    dir * width * 0.22 * effectAmount, duration, entering);
            cl_add_effect_animation(animations, "transform.rotation.y",
                                    dir * pi * 0.82 * effectAmount, duration, entering);
            cl_add_opacity_animation(animations, minOpacity, duration, entering);
            break;
        case CylinderLiteEffectTurn:
            cl_add_effect_animation(animations, "transform.translation.x",
                                    dir * width * 0.18 * effectAmount, duration, entering);
            cl_add_effect_animation(animations, "transform.rotation.y",
                                    -dir * pi * 0.58 * effectAmount, duration, entering);
            break;
        case CylinderLiteEffectZoomFadeOut:
        default:
            cl_add_basic_animation(animations, "transform.scale",
                                   entering ? minScale : 1.0,
                                   entering ? 1.0 : minScale,
                                   duration);
            cl_add_opacity_animation(animations, minOpacity, duration, entering);
            break;
        case CylinderLiteEffectZoomFadeIn: {
            double maxScale = 1.0 + (1.0 - minScale) * 1.55;
            cl_add_basic_animation(animations, "transform.scale",
                                   entering ? maxScale : 1.0,
                                   entering ? 1.0 : maxScale,
                                   duration);
            cl_add_opacity_animation(animations, minOpacity, duration, entering);
            break;
        }
    }

    if (r_msg2_main(animations, "count", 0, 0, 0, 0) == 0) return 0;

    r_msg2_main(group, "setAnimations:", animations, 0, 0, 0);
    r_msg2_main_raw(group, "setDuration:",
                    &duration, sizeof(duration),
                    NULL, 0, NULL, 0, NULL, 0);
    uint64_t fillMode = r_nsstr_retained("both");
    if (r_is_objc_ptr(fillMode)) {
        r_msg2_main(group, "setFillMode:", fillMode, 0, 0, 0);
        r_msg2(fillMode, "release", 0, 0, 0, 0);
    }
    BOOL removed = NO;
    r_msg2_main_raw(group, "setRemovedOnCompletion:",
                    &removed, sizeof(removed),
                    NULL, 0, NULL, 0, NULL, 0);

    uint64_t retained = r_msg2_main(group, "retain", 0, 0, 0, 0);
    return r_is_objc_ptr(retained) ? retained : 0;
}

static void cl_release_animation_templates(void)
{
    for (int i = 0; i < 2; i++) {
        if (r_is_objc_ptr(s_cylinderlite_enter_animations[i]))
            r_msg2_main(s_cylinderlite_enter_animations[i], "release", 0, 0, 0, 0);
        if (r_is_objc_ptr(s_cylinderlite_exit_animations[i]))
            r_msg2_main(s_cylinderlite_exit_animations[i], "release", 0, 0, 0, 0);
        s_cylinderlite_enter_animations[i] = 0;
        s_cylinderlite_exit_animations[i] = 0;
    }
    if (r_is_objc_ptr(s_cylinderlite_animation_key))
        r_msg2(s_cylinderlite_animation_key, "release", 0, 0, 0, 0);
    s_cylinderlite_animation_key = 0;
}

static bool cl_prepare_animation_templates(CylinderLiteEffect effect)
{
    printf("[CYLINDERLITE] preparing animation templates effect=%d\n", (int)effect);
    cl_release_animation_templates();
    s_cylinderlite_animation_key = r_nsstr_retained(kCylinderLiteAnimationKey.UTF8String);
    if (!r_is_objc_ptr(s_cylinderlite_animation_key)) {
        printf("[CYLINDERLITE] preparing animation templates failed: missing key\n");
        return false;
    }

    for (int i = 0; i < 2; i++) {
        int direction = i == 0 ? -1 : 1;
        printf("[CYLINDERLITE] preparing template direction=%d enter\n", direction);
        s_cylinderlite_enter_animations[i] = cl_build_page_animation(effect, direction, true);
        printf("[CYLINDERLITE] preparing template direction=%d exit\n", direction);
        s_cylinderlite_exit_animations[i] = cl_build_page_animation(effect, direction, false);
        if (!r_is_objc_ptr(s_cylinderlite_enter_animations[i]) ||
            !r_is_objc_ptr(s_cylinderlite_exit_animations[i])) {
            cl_release_animation_templates();
            printf("[CYLINDERLITE] preparing animation templates failed direction=%d\n", direction);
            return false;
        }
    }
    printf("[CYLINDERLITE] preparing animation templates done\n");
    return true;
}

static bool cl_add_prepared_animation(uint64_t listView, uint64_t animation)
{
    if (!r_is_objc_ptr(animation) || !r_is_objc_ptr(s_cylinderlite_animation_key)) return false;
    uint64_t layer = cl_safe_msg(listView, "layer", 0, 0, 0, 0);
    if (!r_is_objc_ptr(layer)) return false;

    r_msg2_main(layer, "removeAnimationForKey:", s_cylinderlite_animation_key, 0, 0, 0);
    r_msg2_main(layer, "addAnimation:forKey:", animation, s_cylinderlite_animation_key, 0, 0);
    return true;
}

static void cl_set_animation_progress(uint64_t listView, double progress)
{
    (void)listView;
    (void)progress;
}

static void cl_set_view_alpha(uint64_t view, double alpha)
{
    if (!r_is_objc_ptr(view) || !r_responds_main(view, "setAlpha:")) return;
    if (alpha < 0.0) alpha = 0.0;
    if (alpha > 1.0) alpha = 1.0;
    r_msg2_main_raw(view, "setAlpha:",
                    &alpha, sizeof(alpha),
                    NULL, 0, NULL, 0, NULL, 0);
}

static void cl_set_view_transform(uint64_t view, double scale, double tx)
{
    if (!r_is_objc_ptr(view) || !r_responds_main(view, "setTransform:")) return;
    CLTransform t = { scale, 0.0, 0.0, scale, tx, 0.0 };
    r_msg2_main_raw(view, "setTransform:",
                    &t, sizeof(t),
                    NULL, 0, NULL, 0, NULL, 0);
}

static void cl_reset_view_visual(uint64_t view)
{
    cl_set_view_alpha(view, 1.0);
    cl_set_view_transform(view, 1.0, 0.0);
}

static void cl_remove_prepared_animation(uint64_t listView)
{
    if (!r_is_objc_ptr(listView) || !r_is_objc_ptr(s_cylinderlite_animation_key)) return;
    uint64_t layer = cl_safe_msg(listView, "layer", 0, 0, 0, 0);
    if (!r_is_objc_ptr(layer)) return;
    r_msg2_main(layer, "removeAnimationForKey:", s_cylinderlite_animation_key, 0, 0, 0);
    cl_reset_view_visual(listView);
}

static void cl_clear_one_shot_cleanup(bool removeAnimations)
{
    if (removeAnimations) {
        cl_remove_prepared_animation(s_cylinderlite_one_shot_cleanup_from_list);
        cl_remove_prepared_animation(s_cylinderlite_one_shot_cleanup_to_list);
    }
    s_cylinderlite_one_shot_cleanup_from_list = 0;
    s_cylinderlite_one_shot_cleanup_to_list = 0;
    s_cylinderlite_one_shot_cleanup_ticks = 0;
}

static void cl_schedule_one_shot_cleanup(uint64_t fromList, uint64_t toList)
{
    cl_clear_one_shot_cleanup(true);
    s_cylinderlite_one_shot_cleanup_from_list = fromList;
    s_cylinderlite_one_shot_cleanup_to_list = toList;
    unsigned int ticks = (unsigned int)((s_cylinderlite_one_shot_duration_ms + 79) / 80) + 2;
    if (ticks < 3) ticks = 3;
    if (ticks > 16) ticks = 16;
    s_cylinderlite_one_shot_cleanup_ticks = ticks;
}

static void cl_tick_one_shot_cleanup(void)
{
    if (s_cylinderlite_one_shot_cleanup_ticks == 0) return;
    s_cylinderlite_one_shot_cleanup_ticks--;
    if (s_cylinderlite_one_shot_cleanup_ticks == 0) {
        cl_clear_one_shot_cleanup(true);
        printf("[CYLINDERLITE] one-shot animations cleaned after commit\n");
    }
}

static void cl_remove_cached_page_animations(void)
{
    for (int i = 0; i < s_cylinderlite_list_count; i++) {
        cl_remove_prepared_animation(s_cylinderlite_lists[i]);
    }
    cl_remove_prepared_animation(s_cylinderlite_last_list);
    cl_remove_prepared_animation(s_cylinderlite_one_shot_cleanup_from_list);
    cl_remove_prepared_animation(s_cylinderlite_one_shot_cleanup_to_list);
}

static void cl_clear_page_cache(void)
{
    s_cylinderlite_scroll = 0;
    s_cylinderlite_pan = 0;
    memset(s_cylinderlite_lists, 0, sizeof(s_cylinderlite_lists));
    memset(s_cylinderlite_list_x, 0, sizeof(s_cylinderlite_list_x));
    s_cylinderlite_list_count = 0;
    s_cylinderlite_page_width = 0.0;
    s_cylinderlite_gesture_animating = false;
    s_cylinderlite_gesture_from_page = -1;
    s_cylinderlite_gesture_to_page = -1;
    s_cylinderlite_finish_animating = false;
    s_cylinderlite_finish_from_page = -1;
    s_cylinderlite_finish_to_page = -1;
    s_cylinderlite_finish_progress = 0.0;
    s_cylinderlite_finish_target = 0.0;
    s_cylinderlite_idle_ticks = 0;
    cl_clear_one_shot_cleanup(false);
}

static bool cl_refresh_page_cache(void)
{
    cl_restore_follow_pages();
    cl_clear_page_cache();

    uint64_t scrollClass = r_class("SBIconScrollView");
    uint64_t listClass = r_class("SBIconListView");
    if (!r_is_objc_ptr(scrollClass) || !r_is_objc_ptr(listClass)) return false;

    uint64_t scrolls[16] = {0};
    int scrollCount = sb_collect_views_in_windows(scrollClass, scrolls, 16);
    uint32_t oldSettle = r_settle_us(0);

    uint64_t bestScroll = 0;
    uint64_t bestLists[16] = {0};
    double bestListX[16] = {0};
    int bestCount = 0;
    double bestWidth = 0.0;
    double bestPageWidth = 0.0;

    for (int i = 0; i < scrollCount; i++) {
        uint64_t scroll = scrolls[i];
        CLRect bounds = {0};
        CLSize content = {0};
        if (!cl_get_rect(scroll, "bounds", &bounds) ||
            !cl_get_size(scroll, "contentSize", &content) ||
            bounds.width <= 1.0 ||
            content.width <= bounds.width + 1.0) {
            continue;
        }

        uint64_t lists[16] = {0};
        int listCount = sb_collect_views(scroll, listClass, lists, 16);
        if (listCount <= 0) continue;
        double listX[16] = {0};
        int usableCount = 0;
        for (int j = 0; j < listCount; j++) {
            CLRect frame = {0};
            if (!cl_get_rect(lists[j], "frame", &frame)) continue;
            uint64_t parent = cl_safe_msg(lists[j], "superview", 0, 0, 0, 0);
            if (parent != scroll) {
                CLRect converted = {0};
                if (!r_is_objc_ptr(parent) ||
                    !r_msg2_main_struct_ret(parent, "convertRect:toView:",
                        &converted, sizeof(converted), &frame, sizeof(frame),
                        &scroll, sizeof(scroll), NULL, 0, NULL, 0)) continue;
                frame = converted;
            }
            lists[usableCount] = lists[j];
            listX[usableCount] = frame.x;
            usableCount++;
        }
        if (usableCount <= 0) continue;
        if (content.width > bestWidth) {
            bestScroll = scroll;
            bestWidth = content.width;
            bestPageWidth = bounds.width;
            bestCount = usableCount;
            memset(bestLists, 0, sizeof(bestLists));
            memset(bestListX, 0, sizeof(bestListX));
            memcpy(bestLists, lists, sizeof(uint64_t) * (size_t)usableCount);
            memcpy(bestListX, listX, sizeof(double) * (size_t)usableCount);
        }
    }

    r_settle_us(oldSettle);
    if (!bestScroll || bestCount <= 0) return false;

    s_cylinderlite_scroll = bestScroll;
    s_cylinderlite_pan = cl_safe_msg(bestScroll, "panGestureRecognizer", 0, 0, 0, 0);
    s_cylinderlite_list_count = bestCount;
    s_cylinderlite_page_width = bestPageWidth;
    memcpy(s_cylinderlite_lists, bestLists, sizeof(uint64_t) * (size_t)bestCount);
    memcpy(s_cylinderlite_list_x, bestListX, sizeof(double) * (size_t)bestCount);
    uint64_t screen = cl_safe_msg(r_class("UIScreen"), "mainScreen", 0, 0, 0, 0);
    CLRect screenBounds = {0};
    s_perspective_distance = cl_get_rect(screen, "bounds", &screenBounds)
        ? (screenBounds.width + screenBounds.height) / 2 : 0;
    printf("[CYLINDERLITE] cached scroll=0x%llx pan=0x%llx lists=%d pageWidth=%.1f\n",
           (unsigned long long)s_cylinderlite_scroll,
           (unsigned long long)s_cylinderlite_pan,
           s_cylinderlite_list_count,
           s_cylinderlite_page_width);
    return r_is_objc_ptr(s_cylinderlite_pan);
}

static uint64_t cl_list_for_page(int page)
{
    if (page < 0 || s_cylinderlite_page_width <= 1.0) return 0;
    double targetX = (double)page * s_cylinderlite_page_width;
    uint64_t bestList = 0;
    double bestDistance = DBL_MAX;
    for (int i = 0; i < s_cylinderlite_list_count; i++) {
        double distance = fabs(s_cylinderlite_list_x[i] - targetX);
        if (distance < bestDistance) {
            bestDistance = distance;
            bestList = s_cylinderlite_lists[i];
        }
    }
    return bestDistance <= s_cylinderlite_page_width * 0.55 ? bestList : 0;
}

static uint64_t cl_find_current_page_list(int *pageOut, int *directionOut)
{
    if (pageOut) *pageOut = -1;
    if (directionOut) *directionOut = 1;

    if (!s_cylinderlite_scroll || s_cylinderlite_list_count <= 0) {
        if (!cl_refresh_page_cache()) return 0;
    }

    CLPoint offset = {0};
    if (s_cylinderlite_page_width <= 1.0 ||
        !cl_get_point_fast(s_cylinderlite_scroll, "contentOffset", &offset)) {
        if (!cl_refresh_page_cache()) return 0;
        if (s_cylinderlite_page_width <= 1.0 ||
            !cl_get_point_fast(s_cylinderlite_scroll, "contentOffset", &offset)) {
            return 0;
        }
    }

    int page = (int)llround(offset.x / s_cylinderlite_page_width);
    uint64_t bestList = cl_list_for_page(page);

    if (!bestList) return 0;

    if (pageOut) *pageOut = page;
    if (directionOut) {
        if (s_cylinderlite_last_page != -9999 && page != s_cylinderlite_last_page) {
            *directionOut = page < s_cylinderlite_last_page ? -1 : 1;
        } else {
            *directionOut = 1;
        }
    }
    return bestList;
}

static void cl_write_layer(CLPageVisual *page, CATransform3D transform, double opacity, double offset)
{
    // Stage locally. No layer setter is sent until all affected pages are ready.
    CLFrameValues *values = &s_frame_values[page - s_page_visuals];
    values->position = page->position;
    values->position.x += offset;
    values->transform = transform;
    // CALayer.opacity is a float, unlike UIView.alpha (CGFloat).
    values->opacity = (float)fmax(0.0, fmin(1.0, opacity));
}

static void cl_release_owned(uint64_t *object)
{
    if (r_is_objc_ptr(*object)) r_msg2(*object, "release", 0, 0, 0, 0);
    *object = 0;
}

// Build once, not once per property per frame. These invocations own their
// targets, and are never modified while the main thread is executing a batch.
static uint64_t cl_cached_invocation(uint64_t target, const char *name,
                                      const void *argument, size_t size)
{
    uint64_t selector = r_sel(name);
    uint64_t signature = r_msg2(target, "methodSignatureForSelector:", selector, 0, 0, 0);
    if (!r_is_objc_ptr(signature)) return 0;
    uint64_t invocation = r_msg2(r_class("NSInvocation"), "invocationWithMethodSignature:",
                                signature, 0, 0, 0);
    if (!r_is_objc_ptr(invocation)) return 0;
    invocation = r_msg2(invocation, "retain", 0, 0, 0, 0);
    if (!r_is_objc_ptr(invocation)) return 0;
    r_msg2(invocation, "setTarget:", target, 0, 0, 0);
    if (!remote_call_current_success()) { cl_release_owned(&invocation); return 0; }
    r_msg2(invocation, "setSelector:", selector, 0, 0, 0);
    if (!remote_call_current_success()) { cl_release_owned(&invocation); return 0; }
    if (size) {
        if (!s_frame_memory || size > sizeof(s_frame_values) ||
            !remote_write(s_frame_memory, argument, size)) {
            cl_release_owned(&invocation);
            return 0;
        }
        r_msg2(invocation, "setArgument:atIndex:", s_frame_memory, 2, 0, 0);
        if (!remote_call_current_success()) {
            cl_release_owned(&invocation);
            return 0;
        }
    }
    r_msg2(invocation, "retainArguments", 0, 0, 0, 0);
    if (!remote_call_current_success()) { cl_release_owned(&invocation); return 0; }
    return invocation;
}

static bool cl_submit_frame(uint32_t mask)
{
    if (!mask) return true;
    if (!s_frame_memory || !s_transaction_begin || !s_transaction_disable ||
        !s_transaction_commit) return false;

    // Usually the same pair of pages is visible for an entire swipe. Rebuild
    // only when that set changes (including a departing page needing reset).
    if (!s_frame_batch || s_batch_mask != mask) {
        uint64_t objects[3 + 16 * 3];
        size_t count = 0;
        objects[count++] = s_transaction_begin;
        objects[count++] = s_transaction_disable;
        for (int i = 0; i < 16; i++) if (mask & (1u << i)) {
            for (int j = s_write_position ? 0 : 1; j < 3; j++) {
                if (!r_is_objc_ptr(s_page_visuals[i].setters[j])) return false;
                objects[count++] = s_page_visuals[i].setters[j];
            }
        }
        objects[count++] = s_transaction_commit;
        if (!remote_write(s_frame_memory, objects, count * sizeof(uint64_t))) return false;
        uint64_t batch = r_msg2(r_class("NSArray"), "alloc", 0, 0, 0, 0);
        batch = r_msg2(batch, "initWithObjects:count:", s_frame_memory, count, 0, 0);
        if (!r_is_objc_ptr(batch)) return false;
        cl_release_owned(&s_frame_batch);
        s_frame_batch = batch;
        s_batch_mask = mask;
    }

    // One memory transfer for the frame. setArgument copies bytes into the
    // cached invocation; the scratch storage is not referenced during invoke.
    if (!remote_write(s_frame_memory, s_frame_values, sizeof(s_frame_values))) return false;
    const size_t offsets[3] = { offsetof(CLFrameValues, position),
                               offsetof(CLFrameValues, transform),
                               offsetof(CLFrameValues, opacity) };
    uint64_t setArg = r_sel("setArgument:atIndex:");
    for (int i = 0; i < 16; i++) if (mask & (1u << i)) {
        for (int j = s_write_position ? 0 : 1; j < 3; j++) {
            r_msg(s_page_visuals[i].setters[j], setArg,
                  s_frame_memory + i * sizeof(CLFrameValues) + offsets[j], 2, 0, 0);
            if (!remote_call_current_success()) return false;
        }
    }

    // NSArray invokes in order. begin -> disableActions -> all setters -> commit
    // runs within ONE main-thread dispatch. Never leave a transaction open
    // between remote calls, and never pause the scroll layer's clock.
    r_perform_main(s_frame_batch, r_sel("makeObjectsPerformSelector:"), r_sel("invoke"), true);
    return remote_call_current_success();
}

static void cl_restore_follow_pages(void)
{
    uint32_t oldSettle = r_settle_us(0);
    uint32_t mask = 0;
    for (int i = 0; i < 16; i++) {
        CLPageVisual *page = &s_page_visuals[i];
        if (page->modified) {
            cl_write_layer(page, page->transform, page->opacity, 0);
            mask |= 1u << i;
        }
    }
    if (!cl_submit_frame(mask))
        log_user("[CYLINDERLITE] Could not confirm page restoration; stop/reapply or respring if icons remain altered.\n");
    cl_release_owned(&s_frame_batch);
    for (int i = 0; i < 16; i++) {
        for (int j = 0; j < 3; j++) cl_release_owned(&s_page_visuals[i].setters[j]);
        // Release retained UI layers on the main thread.
        if (s_page_visuals[i].layer)
            r_msg2_main(s_page_visuals[i].layer, "release", 0, 0, 0, 0);
    }
    // The offset invocation retains a UIView target; final release belongs on main.
    if (s_offset_invocation) r_msg2_main(s_offset_invocation, "release", 0, 0, 0, 0);
    s_offset_invocation = 0;
    cl_release_owned(&s_transaction_begin);
    cl_release_owned(&s_transaction_disable);
    cl_release_owned(&s_transaction_commit);
    if (s_frame_memory) r_free(s_frame_memory);
    s_frame_memory = 0;
    s_batch_mask = 0;
    if (s_frame_count) printf("[CYLINDERLITE] v2 frames=%u workMean=%.1fms workMax=%.1fms (excludes poll sleep)\n",
        s_frame_count, s_frame_total_ms / s_frame_count, s_frame_max_ms);
    s_frame_count = 0;
    s_frame_total_ms = s_frame_max_ms = 0;
    memset(s_page_visuals, 0, sizeof(s_page_visuals));
    s_last_offset = NAN;
    r_settle_us(oldSettle);
}

static bool cl_capture_page(int index)
{
    CLPageVisual *page = &s_page_visuals[index];
    if (page->layer) return true;
    uint64_t layer = cl_safe_msg(s_cylinderlite_lists[index], "layer", 0, 0, 0, 0);
    CLRect bounds = {0};
    CATransform3D transform;
    float opacity = 1;
    CLPoint position;
    if (!r_is_objc_ptr(layer) || !cl_get_rect(layer, "bounds", &bounds) ||
        !cl_get_point(layer, "position", &position) ||
        bounds.width <= 1 || bounds.height <= 1 ||
        !r_msg2_main_struct_ret(layer, "transform", &transform, sizeof(transform),
                                NULL, 0, NULL, 0, NULL, 0, NULL, 0) ||
        !r_msg2_main_struct_ret(layer, "opacity", &opacity, sizeof(opacity),
                                NULL, 0, NULL, 0, NULL, 0, NULL, 0)) return false;
    page->layer = r_msg2_main(layer, "retain", 0, 0, 0, 0);
    page->transform = transform;
    page->position = position;
    page->opacity = opacity;
    page->width = bounds.width;
    page->height = bounds.height;
    if (!r_is_objc_ptr(page->layer)) return false;
    if (s_write_position)
        page->setters[0] = cl_cached_invocation(layer, "setPosition:", &position, sizeof(position));
    page->setters[1] = cl_cached_invocation(layer, "setTransform:", &transform, sizeof(transform));
    page->setters[2] = cl_cached_invocation(layer, "setOpacity:", &opacity, sizeof(opacity));
    return (!s_write_position || page->setters[0]) && page->setters[1] && page->setters[2];
}

static bool cl_prepare_follow_renderer(void)
{
    uint32_t oldSettle = r_settle_us(0);
    s_write_position = s_cylinderlite_effect == CylinderLiteEffectCubeInside ||
        s_cylinderlite_effect == CylinderLiteEffectCubeOutside ||
        s_cylinderlite_effect == CylinderLiteEffectCardHorizontal ||
        s_cylinderlite_effect == CylinderLiteEffectCardVertical ||
        s_cylinderlite_effect == CylinderLiteEffectHinge;
    s_frame_memory = r_dlsym_call(R_TIMEOUT, "malloc", sizeof(s_frame_values), 0, 0, 0, 0, 0, 0, 0);
    bool ok = s_frame_memory != 0;
    if (ok) {
        BOOL disable = YES;
        uint64_t transaction = r_class("CATransaction");
        s_transaction_begin = cl_cached_invocation(transaction, "begin", NULL, 0);
        s_transaction_disable = cl_cached_invocation(transaction, "setDisableActions:", &disable, sizeof(disable));
        s_transaction_commit = cl_cached_invocation(transaction, "commit", NULL, 0);
        s_offset_invocation = cl_cached_invocation(s_cylinderlite_scroll, "contentOffset", NULL, 0);
        ok = s_transaction_begin && s_transaction_disable && s_transaction_commit && s_offset_invocation;
    }
    // Pay discovery/allocation costs at Apply, not on the first swipe to a page.
    for (int i = 0; ok && i < s_cylinderlite_list_count; i++) ok = cl_capture_page(i);
    if (!ok) cl_restore_follow_pages();
    r_settle_us(oldSettle);
    return ok;
}

static bool cl_read_follow_offset(CLPoint *offset)
{
    if (!s_offset_invocation || !s_frame_memory) return false;
    r_perform_main(s_offset_invocation, r_sel("invoke"), 0, true);
    if (!remote_call_current_success()) return false;
    r_msg2(s_offset_invocation, "getReturnValue:", s_frame_memory, 0, 0, 0);
    return remote_call_current_success() && remote_read(s_frame_memory, offset, sizeof(*offset)) &&
        isfinite(offset->x) && isfinite(offset->y);
}

// Page formulas adapted from Cylinder-Remade's CylinderAnimator.swift.
// Offset has the same sign as upstream: contentOffset.x - page.frame.origin.x.
// Position compensation is applied separately, as in the original: translation
// inside a perspective matrix is not equivalent to moving the layer position.
static void cl_follow_effect(CLPageVisual *page, double offset)
{
    double p = offset / page->width;
    double q = fabs(p);
    double strength = s_cylinderlite_intensity_pct / 100.0;
    double angle = p * M_PI;
    double compensation = 0;
    double alpha = 1;
    CATransform3D t = CATransform3DIdentity;
    double perspective = s_perspective_distance > 1 ? s_perspective_distance
        : (s_cylinderlite_page_width + page->height) / 2.0;
    switch (s_cylinderlite_effect) {
        case CylinderLiteEffectBackwards:
            t = CATransform3DMakeTranslation(2 * offset, 0, 0);
            break;
        case CylinderLiteEffectCubeInside:
        case CylinderLiteEffectCubeOutside: {
            bool outside = s_cylinderlite_effect == CylinderLiteEffectCubeOutside;
            angle = p * M_PI_2;
            double h = page->width / 2;
            double x = h * cos(fabs(angle)) - h;
            double z = h * sin(fabs(angle)) * (outside ? -1 : 1);
            if (p > 0) x = -x;
            x -= offset;
            compensation = offset;
            t = CATransform3DMakeTranslation(x, 0, z);
            t.m44 = 1 - z / perspective;
            t.m34 = -1 / perspective;
            t = CATransform3DRotate(t, outside ? -angle : angle, 0, 1, 0);
            if (outside) {
                double threshold = atan2(perspective - z, fabs(x));
                if (fabs(angle) > threshold && M_PI_2 - threshold > 1e-6)
                    alpha = 1 - (fabs(angle) - threshold) / (M_PI_2 - threshold);
            }
            break;
        }
        case CylinderLiteEffectCardHorizontal:
        case CylinderLiteEffectCardVertical: {
            bool vertical = s_cylinderlite_effect == CylinderLiteEffectCardVertical;
            compensation = offset;
            alpha = q >= 0.5 ? 0 : 1;
            t.m34 = -1 / perspective;
            t = CATransform3DRotate(t, vertical ? angle : -angle,
                                    vertical ? 1 : 0, vertical ? 0 : 1, 0);
            break;
        }
        case CylinderLiteEffectHinge: {
            compensation = offset;
            double x = p > 0 ? -page->width / 2 : page->width / 2;
            t = CATransform3DMakeTranslation(x, 0, 0);
            t.m34 = -1 / perspective;
            t = CATransform3DRotate(t, angle, 0, 1, 0);
            t = CATransform3DTranslate(t, -x, 0, 0);
            break;
        }
        case CylinderLiteEffectPageFlip:
        case CylinderLiteEffectPageTwist: {
            bool twist = s_cylinderlite_effect == CylinderLiteEffectPageTwist;
            alpha = 1 - q;
            t.m34 = -1 / perspective;
            t = CATransform3DRotate(t, twist ? -2.0 / 3.0 * angle : angle,
                                    twist ? 1 : 0, twist ? 0 : 1, 0);
            break;
        }
        case CylinderLiteEffectVerticalScroll:
            t = CATransform3DMakeTranslation(offset, p * page->height, 0);
            alpha = 1 - q;
            break;
        // Cyanide-specific effects: keep these distinct from upstream ports.
        case CylinderLiteEffectSlide:
            alpha = 1 - q * (1 - s_cylinderlite_opacity_pct / 100.0);
            break;
        case CylinderLiteEffectFlip:
            t = CATransform3DMakeScale(fmax(0.01, 1 - q * strength), 1, 1);
            break;
        case CylinderLiteEffectPageSpin:
            t = CATransform3DMakeRotation(2 * angle * strength, 0, 0, 1);
            break;
        case CylinderLiteEffectWheel:
            // Legacy page-level approximation; upstream Wheel moves each icon.
            t = CATransform3DMakeRotation(-angle * 0.35 * strength, 0, 0, 1);
            break;
        case CylinderLiteEffectHellaFar:
            t = CATransform3DMakeTranslation(-offset, 0, 0);
            break;
        case CylinderLiteEffectTurn:
            t.m34 = -1 / perspective;
            t = CATransform3DRotate(t, -angle / 2, 0, 1, 0);
            break;
        case CylinderLiteEffectZoomFadeIn:
        case CylinderLiteEffectZoomFadeOut: {
            double scale = s_cylinderlite_effect == CylinderLiteEffectZoomFadeIn
                ? 1 + q * (1 - strength) * 1.55 : 1 - q * (1 - strength);
            t = CATransform3DMakeScale(scale, scale, 1);
            alpha = 1 - q * (1 - s_cylinderlite_opacity_pct / 100.0);
            break;
        }
    }
    cl_write_layer(page, CATransform3DConcat(t, page->transform), alpha * page->opacity, compensation);
    page->modified = true;
}

static bool cl_tick_follow(void)
{
    if (!s_offset_invocation && !cl_prepare_follow_renderer()) return false;
    double started = CACurrentMediaTime();
    CLPoint offset;
    if (!cl_read_follow_offset(&offset)) return false;
    if (isfinite(s_last_offset) && fabs(offset.x - s_last_offset) < 0.01) return true;
    uint32_t mask = 0, restoredMask = 0;
    for (int i = 0; i < s_cylinderlite_list_count; i++) {
        CLPageVisual *page = &s_page_visuals[i];
        double delta = offset.x - s_cylinderlite_list_x[i];
        // Follow actual offset through dragging, reversal, cancellation and
        // deceleration. No gesture-state gate or synthetic finish animation.
        bool visible = s_cylinderlite_list_x[i] < offset.x + s_cylinderlite_page_width &&
                       s_cylinderlite_list_x[i] + s_cylinderlite_page_width > offset.x;
        if (visible && fabs(delta) > 0.5) {
            cl_follow_effect(page, delta);
            mask |= 1u << i;
        } else if (page->modified) {
            cl_write_layer(page, page->transform, page->opacity, 0);
            mask |= 1u << i;
            restoredMask |= 1u << i;
        }
    }
    if (!cl_submit_frame(mask)) return false;
    for (int i = 0; i < 16; i++) if (restoredMask & (1u << i)) s_page_visuals[i].modified = false;
    s_last_offset = offset.x;
    if (mask) {
        double elapsed = (CACurrentMediaTime() - started) * 1000;
        s_frame_count++;
        s_frame_total_ms += elapsed;
        s_frame_max_ms = fmax(s_frame_max_ms, elapsed);
    }
    return true;
}

bool cylinderlite_tick_in_session(void)
{
    if (!s_cylinderlite_active) return false;
    if (!r_is_objc_ptr(s_cylinderlite_pan) || s_cylinderlite_page_width <= 1.0) {
        if (!cl_refresh_page_cache()) return false;
    }

    uint32_t oldSettle = r_settle_us(0);
    if (s_cylinderlite_follow_gesture) {
        bool ok = cl_tick_follow();
        r_settle_us(oldSettle);
        return ok;
    }
    uint64_t state = r_msg2_main(s_cylinderlite_pan, "state", 0, 0, 0, 0);
    bool gestureActive = state == 1 || state == 2;
    bool scrollSettling = !gestureActive &&
                          s_cylinderlite_gesture_animating &&
                          (cl_get_bool(s_cylinderlite_scroll, "isTracking") ||
                           cl_get_bool(s_cylinderlite_scroll, "isDragging") ||
                           cl_get_bool(s_cylinderlite_scroll, "isDecelerating"));

    CLPoint offset = {0};
    bool haveOffset = false;
    if (gestureActive || s_cylinderlite_gesture_animating) {
        haveOffset = cl_get_point_fast(s_cylinderlite_scroll, "contentOffset", &offset);
        if (!haveOffset) {
            r_settle_us(oldSettle);
            return false;
        }
    }

    if (gestureActive && s_cylinderlite_finish_animating) {
        cl_remove_prepared_animation(cl_list_for_page(s_cylinderlite_finish_from_page));
        cl_remove_prepared_animation(cl_list_for_page(s_cylinderlite_finish_to_page));
        s_cylinderlite_finish_animating = false;
        s_cylinderlite_finish_from_page = -1;
        s_cylinderlite_finish_to_page = -1;
        s_cylinderlite_finish_progress = 0.0;
        s_cylinderlite_finish_target = 0.0;
    }
    if (gestureActive && s_cylinderlite_one_shot_cleanup_ticks > 0) {
        cl_clear_one_shot_cleanup(true);
    }

    if (!gestureActive && s_cylinderlite_finish_animating) {
        double delta = s_cylinderlite_finish_target - s_cylinderlite_finish_progress;
        double step = fabs(delta) < 0.34 ? delta : (delta < 0.0 ? -0.34 : 0.34);
        s_cylinderlite_finish_progress += step;
        if (s_cylinderlite_finish_progress < 0.0) s_cylinderlite_finish_progress = 0.0;
        if (s_cylinderlite_finish_progress > 1.0) s_cylinderlite_finish_progress = 1.0;

        uint64_t fromList = cl_list_for_page(s_cylinderlite_finish_from_page);
        uint64_t toList = cl_list_for_page(s_cylinderlite_finish_to_page);
        cl_set_animation_progress(fromList, s_cylinderlite_finish_progress);
        cl_set_animation_progress(toList, s_cylinderlite_finish_progress);

        if (fabs(s_cylinderlite_finish_progress - s_cylinderlite_finish_target) <= 0.001) {
            cl_remove_prepared_animation(fromList);
            cl_remove_prepared_animation(toList);
            printf("[CYLINDERLITE] finish complete target=%.2f\n",
                   s_cylinderlite_finish_target);
            s_cylinderlite_finish_animating = false;
            s_cylinderlite_finish_from_page = -1;
            s_cylinderlite_finish_to_page = -1;
            s_cylinderlite_finish_progress = 0.0;
            s_cylinderlite_finish_target = 0.0;
        }

        s_cylinderlite_idle_ticks = 0;
        r_settle_us(oldSettle);
        return true;
    }

    if (gestureActive && !s_cylinderlite_gesture_animating) {

        double originX = (double)s_cylinderlite_last_page * s_cylinderlite_page_width;
        double delta = offset.x - originX;
        double threshold = fmax(3.0, s_cylinderlite_page_width * 0.008);
        if (fabs(delta) >= threshold) {
            int direction = delta < 0.0 ? -1 : 1;
            int targetPage = s_cylinderlite_last_page + direction;
            uint64_t fromList = cl_list_for_page(s_cylinderlite_last_page);
            uint64_t toList = cl_list_for_page(targetPage);
            int templateIndex = direction < 0 ? 0 : 1;
            bool outgoingOK = false;
            bool incomingOK = false;
            if (r_is_objc_ptr(fromList) && r_is_objc_ptr(toList)) {
                outgoingOK = cl_add_prepared_animation(
                    fromList, s_cylinderlite_exit_animations[templateIndex]);
                incomingOK = cl_add_prepared_animation(
                    toList, s_cylinderlite_enter_animations[templateIndex]);
            }

            if (outgoingOK && incomingOK) {
                s_cylinderlite_gesture_animating = true;
                s_cylinderlite_gesture_from_page = s_cylinderlite_last_page;
                s_cylinderlite_gesture_to_page = targetPage;
                double progress = fabs(delta) / s_cylinderlite_page_width;
                cl_set_animation_progress(fromList, progress);
                cl_set_animation_progress(toList, progress);
                printf("[CYLINDERLITE] gesture start state=%llu from=%d to=%d direction=%d effect=%d\n",
                       (unsigned long long)state,
                       s_cylinderlite_gesture_from_page,
                       s_cylinderlite_gesture_to_page,
                       direction,
                       (int)s_cylinderlite_effect);
            }
        }
        s_cylinderlite_idle_ticks = 0;
        r_settle_us(oldSettle);
        return true;
    }

    if (gestureActive && s_cylinderlite_gesture_animating) {
        double originX = (double)s_cylinderlite_gesture_from_page * s_cylinderlite_page_width;
        double progress = fabs(offset.x - originX) / s_cylinderlite_page_width;
        uint64_t fromList = cl_list_for_page(s_cylinderlite_gesture_from_page);
        uint64_t toList = cl_list_for_page(s_cylinderlite_gesture_to_page);
        cl_set_animation_progress(fromList, progress);
        cl_set_animation_progress(toList, progress);
        s_cylinderlite_idle_ticks = 0;
        r_settle_us(oldSettle);
        return true;
    }

    if (scrollSettling) {
        s_cylinderlite_idle_ticks = 0;
        r_settle_us(oldSettle);
        return true;
    }

    if (!gestureActive && s_cylinderlite_gesture_animating) {
        int settledPage = s_cylinderlite_gesture_from_page;
        if (haveOffset) {
            settledPage = (int)llround(offset.x / s_cylinderlite_page_width);
        }
        bool committed = settledPage == s_cylinderlite_gesture_to_page;
        double currentProgress = fabs(offset.x - (double)s_cylinderlite_gesture_from_page * s_cylinderlite_page_width) / s_cylinderlite_page_width;
        if (currentProgress < 0.0) currentProgress = 0.0;
        if (currentProgress > 1.0) currentProgress = 1.0;
        s_cylinderlite_finish_animating = false;
        s_cylinderlite_finish_from_page = s_cylinderlite_gesture_from_page;
        s_cylinderlite_finish_to_page = s_cylinderlite_gesture_to_page;
        s_cylinderlite_finish_progress = currentProgress;
        s_cylinderlite_finish_target = committed ? 1.0 : 0.0;
        uint64_t fromList = cl_list_for_page(s_cylinderlite_gesture_from_page);
        uint64_t toList = cl_list_for_page(s_cylinderlite_gesture_to_page);
        if (!committed) {
            cl_remove_prepared_animation(fromList);
            cl_remove_prepared_animation(toList);
        } else {
            cl_schedule_one_shot_cleanup(fromList, toList);
        }
        uint64_t settledList = cl_list_for_page(settledPage);
        if (r_is_objc_ptr(settledList)) {
            s_cylinderlite_last_page = settledPage;
            s_cylinderlite_last_list = settledList;
        }
        printf("[CYLINDERLITE] gesture end state=%llu settled=%d finish=%s progress=%.2f\n",
               (unsigned long long)state,
               settledPage,
               committed ? "commit" : "rollback",
               currentProgress);
        s_cylinderlite_gesture_animating = false;
        s_cylinderlite_gesture_from_page = -1;
        s_cylinderlite_gesture_to_page = -1;
        s_cylinderlite_idle_ticks = 0;
        r_settle_us(oldSettle);
        return true;
    }

    if (!gestureActive && !s_cylinderlite_gesture_animating &&
        !s_cylinderlite_finish_animating &&
        s_cylinderlite_one_shot_cleanup_ticks > 0) {
        cl_tick_one_shot_cleanup();
        s_cylinderlite_idle_ticks = 0;
        r_settle_us(oldSettle);
        return true;
    }

    // Recover the settled page if background scheduling missed the short gesture states.
    if (!gestureActive && ++s_cylinderlite_idle_ticks >= 6) {
        s_cylinderlite_idle_ticks = 0;
        CLPoint offset = {0};
        if (cl_get_point_fast(s_cylinderlite_scroll, "contentOffset", &offset)) {
            int settledPage = (int)llround(offset.x / s_cylinderlite_page_width);
            uint64_t settledList = cl_list_for_page(settledPage);
            if (r_is_objc_ptr(settledList) && settledPage != s_cylinderlite_last_page) {
                printf("[CYLINDERLITE] gesture states missed; settled page %d -> %d\n",
                       s_cylinderlite_last_page, settledPage);
                s_cylinderlite_last_page = settledPage;
                s_cylinderlite_last_list = settledList;
            }
        }
    }

    r_settle_us(oldSettle);
    return true;
}

bool cylinderlite_apply_in_session_with_options(CylinderLiteEffect effect,
                                                int intensityPct,
                                                int opacityPct,
                                                bool followGesture,
                                                int oneShotDurationMs)
{
    if (effect < CylinderLiteEffectSlide || effect > CylinderLiteEffectLast) {
        effect = CylinderLiteEffectZoomFadeOut;
    }
    cl_remove_cached_page_animations();
    cl_restore_follow_pages();
    s_cylinderlite_effect = effect;
    s_cylinderlite_intensity_pct = cl_clamp_int(intensityPct, 70, 100);
    s_cylinderlite_opacity_pct = cl_clamp_int(opacityPct, 10, 100);
    s_cylinderlite_follow_gesture = followGesture;
    s_cylinderlite_one_shot_duration_ms = cl_clamp_int(oneShotDurationMs, 250, 800);
    s_cylinderlite_active = true;
    s_cylinderlite_last_page = -9999;
    s_cylinderlite_last_list = 0;
    cl_clear_one_shot_cleanup(false);
    cl_clear_page_cache();
    bool cacheOK = cl_refresh_page_cache();
    printf("[CYLINDERLITE] page cache result=%d; preparing templates next\n", cacheOK);
    cl_release_animation_templates();
    bool templatesOK = cacheOK && (followGesture ? cl_prepare_follow_renderer()
                                               : cl_prepare_animation_templates(effect));
    printf("[CYLINDERLITE] templates result=%d; locating current page next\n", templatesOK);
    int page = -1;
    int direction = 1;
    uint64_t list = templatesOK ? cl_find_current_page_list(&page, &direction) : 0;
    printf("[CYLINDERLITE] current page lookup list=0x%llx page=%d direction=%d\n",
           (unsigned long long)list,
           page,
           direction);
    bool ok = templatesOK && r_is_objc_ptr(list) && page >= 0;
    if (ok) {
        s_cylinderlite_last_page = page;
        s_cylinderlite_last_list = list;
        printf("[CYLINDERLITE] armed %s monitor page=%d list=0x%llx pan=0x%llx effect=%d minScale=%d minOpacity=%d durationMs=%d\n",
               s_cylinderlite_follow_gesture ? "v2-batched-progress" : "one-shot",
               page,
               (unsigned long long)list,
               (unsigned long long)s_cylinderlite_pan,
               (int)s_cylinderlite_effect,
               s_cylinderlite_intensity_pct,
               s_cylinderlite_opacity_pct,
               s_cylinderlite_one_shot_duration_ms);
    }
    log_user(ok
        ? "[CYLINDERLITE] Page animation monitor armed. Swipe between Home Screen pages to test it.\n"
        : "[CYLINDERLITE] Could not locate the current Home Screen page.\n");
    s_cylinderlite_active = ok;
    if (!ok) {
        cl_restore_follow_pages();
        cl_release_animation_templates();
        cl_clear_page_cache();
    }
    return ok;
}

bool cylinderlite_apply_in_session(CylinderLiteEffect effect)
{
    return cylinderlite_apply_in_session_with_options(effect, 100, 100, true, 520);
}

bool cylinderlite_stop_in_session(void)
{
    s_cylinderlite_active = false;
    cl_restore_follow_pages();
    uint64_t listClass = r_class("SBIconListView");
    uint64_t key = r_nsstr_retained(kCylinderLiteAnimationKey.UTF8String);
    if (!r_is_objc_ptr(listClass) || !r_is_objc_ptr(key)) {
        if (key) r_msg2(key, "release", 0, 0, 0, 0);
        cl_release_animation_templates();
        s_cylinderlite_last_page = -9999;
        s_cylinderlite_last_list = 0;
        cl_clear_page_cache();
        return false;
    }

    uint64_t lists[32] = {0};
    int count = sb_collect_views_in_windows(listClass, lists, 32);
    for (int i = 0; i < count; i++) {
        uint64_t layer = cl_safe_msg(lists[i], "layer", 0, 0, 0, 0);
        if (r_is_objc_ptr(layer)) {
            r_msg2_main(layer, "removeAnimationForKey:", key, 0, 0, 0);
        }
    }
    if (r_is_objc_ptr(s_cylinderlite_last_list)) {
        uint64_t layer = cl_safe_msg(s_cylinderlite_last_list, "layer", 0, 0, 0, 0);
        if (r_is_objc_ptr(layer)) {
            r_msg2_main(layer, "removeAnimationForKey:", key, 0, 0, 0);
        }
    }
    r_msg2(key, "release", 0, 0, 0, 0);
    cl_release_animation_templates();
    printf("[CYLINDERLITE] stopped removedAnimations=%d\n", count);
    log_user("[CYLINDERLITE] Page animations stopped for this SpringBoard session.\n");
    s_cylinderlite_last_page = -9999;
    s_cylinderlite_last_list = 0;
    cl_clear_page_cache();
    return true;
}

void cylinderlite_forget_remote_state(void)
{
    // SpringBoard is gone: never release or message pointers from the old process.
    s_frame_memory = s_frame_batch = s_offset_invocation = 0;
    s_transaction_begin = s_transaction_disable = s_transaction_commit = 0;
    s_batch_mask = s_frame_count = 0;
    s_frame_total_ms = s_frame_max_ms = 0;
    memset(s_frame_values, 0, sizeof(s_frame_values));
    memset(s_page_visuals, 0, sizeof(s_page_visuals));
    s_last_offset = NAN;
    s_cylinderlite_active = false;
    s_cylinderlite_effect = CylinderLiteEffectZoomFadeOut;
    s_cylinderlite_follow_gesture = true;
    s_cylinderlite_one_shot_duration_ms = 520;
    s_cylinderlite_last_page = -9999;
    s_cylinderlite_last_list = 0;
    memset(s_cylinderlite_enter_animations, 0, sizeof(s_cylinderlite_enter_animations));
    memset(s_cylinderlite_exit_animations, 0, sizeof(s_cylinderlite_exit_animations));
    s_cylinderlite_animation_key = 0;
    cl_clear_page_cache();
}

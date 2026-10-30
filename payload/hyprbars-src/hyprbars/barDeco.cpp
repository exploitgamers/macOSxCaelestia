#include "barDeco.hpp"

#include <hyprland/src/Compositor.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/desktop/state/WindowState.hpp>
#include <hyprland/src/desktop/state/LayerState.hpp>
#include <hyprland/src/desktop/state/ViewHitTester.hpp>
#include <hyprland/src/desktop/view/window/Window.hpp>
#include <hyprland/src/desktop/view/window/WindowPresentation.hpp>
#include <hyprland/src/desktop/view/LayerSurface.hpp>
#include <hyprland/src/helpers/MiscFunctions.hpp>
#include <hyprland/src/keybinds/Manager.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/managers/input/InputManager.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/config/ConfigManager.hpp>
#include <hyprland/src/config/shared/animation/AnimationTree.hpp>
#include <hyprland/src/config/shared/parserUtils/ParserUtils.hpp>
#include <hyprland/src/config/supplementary/executor/Executor.hpp>
#include <hyprland/src/config/shared/actions/ConfigActions.hpp>
#include <hyprland/src/animation/AnimationManager.hpp>
#include <hyprland/src/protocols/LayerShell.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/ipc/s2/S2.hpp>
#include <hyprland/src/managers/fullscreen/FullscreenController.hpp>
#include <hyprland/src/pointer/cursor/CursorShapeOverrideController.hpp>
#include <hyprland/src/layout/LayoutManager.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/state/MonitorState.hpp>

#include "globals.hpp"
#include "BarPassElement.hpp"

#include <climits>

// Announce title-bar drags on the event socket ("custom>>macdrag>>1/0"), the same
// signal Hyprland's mouse:272 binds send for other drags. The bar consumes its
// press, so binds never see it — without this, edge widgets open mid-drag.
static void announceDrag(bool dragging) {
    if (IPC::Socket2::sock())
        IPC::Socket2::sock()->postEvent({"custom", dragging ? "macdrag>>1" : "macdrag>>0"});
}

// Announce plain clicks on the bar ("custom>>macbarclick>>left|right|double"): the bar
// consumes its presses, so Hyprland's mouse binds (the window menu in hypr-qol.lua)
// never see them. The macos shell forwards these to mac_bar_click().
static void announceClick(const char* what) {
    if (IPC::Socket2::sock())
        IPC::Socket2::sock()->postEvent({"custom", std::string("macbarclick>>") + what});
}

static const char* topEdgeCursor(uint8_t edge) {
    if (edge == Layout::CORNER_TOPLEFT)
        return "nw-resize";
    if (edge == Layout::CORNER_TOPRIGHT)
        return "ne-resize";
    return "n-resize";
}

using namespace Render::GL;

static CHyprColor configColor(Config::INTEGER color) {
    return CHyprColor{sc<uint64_t>(color)};
}

CHyprBar::CHyprBar(PHLWINDOW pWindow) : IHyprWindowDecoration(pWindow) {
    m_pWindow = pWindow;

    const auto PMONITOR         = pWindow->m_monitor.lock();
    PMONITOR->m_scheduledRecalc = true;

    // button events
    m_pMouseButtonCallback = Event::bus()->m_events.input.mouse.button.listen([&](IPointer::SButtonEvent e, Event::SCallbackInfo& info) { onMouseButton(info, e); });
    m_pTouchDownCallback   = Event::bus()->m_events.input.touch.down.listen([&](ITouch::SDownEvent e, Event::SCallbackInfo& info) { onTouchDown(info, e); });
    m_pTouchUpCallback     = Event::bus()->m_events.input.touch.up.listen([&](ITouch::SUpEvent e, Event::SCallbackInfo& info) { onTouchUp(info, e); });

    // move events
    m_pTouchMoveCallback = Event::bus()->m_events.input.touch.motion.listen([&](ITouch::SMotionEvent e, Event::SCallbackInfo& info) { onTouchMove(info, e); });
    m_pMouseMoveCallback = Event::bus()->m_events.input.mouse.move.listen([&](Vector2D c, Event::SCallbackInfo& info) { onMouseMove(c); });

    Animation::mgr()->createAnimation(configColor(g_pGlobalState->config.barColor->value()), m_cRealBarColor, Config::animationTree()->getAnimationPropertyConfig("border"),
                                      pWindow, AVARDAMAGE_NONE);
    m_cRealBarColor->setUpdateCallback([&](auto) { damageEntire(); });
}

CHyprBar::~CHyprBar() {
    std::erase(g_pGlobalState->bars, m_self);
}

SDecorationPositioningInfo CHyprBar::getPositioningInfo() {
    const auto                 HEIGHT     = g_pGlobalState->config.barHeight->value();
    const auto                 ENABLED    = g_pGlobalState->config.enabled->value();
    const auto                 PRECEDENCE = g_pGlobalState->config.barPrecedenceOverBorder->value();

    SDecorationPositioningInfo info;
    info.policy         = m_hidden ? DECORATION_POSITION_ABSOLUTE : DECORATION_POSITION_STICKY;
    info.edges          = DECORATION_EDGE_TOP;
    info.priority       = PRECEDENCE ? 10005 : 5000;
    info.reserved       = true;
    info.desiredExtents = {{0, sc<int>(m_hidden || !ENABLED ? 0 : HEIGHT)}, {0, 0}};
    return info;
}

void CHyprBar::onPositioningReply(const SDecorationPositioningReply& reply) {
    if (reply.assignedGeometry.size() != m_bAssignedBox.size())
        m_bWindowSizeChanged = true;

    m_bAssignedBox = reply.assignedGeometry;
}

std::string CHyprBar::getDisplayName() {
    return "Hyprbar";
}

// A window's real box, title bar included, without the border grab padding.
static CBox realBox(const PHLWINDOW& w) {
    return w->getWindowBoxUnified(Desktop::View::RESERVED_EXTENTS);
}

bool CHyprBar::inputIsValid() {
    if (!g_pGlobalState->config.enabled->value() || m_hidden)
        return false;

    if (g_pSeatManager->m_seatGrab && !g_pSeatManager->m_seatGrab->accepts(m_pWindow->wlSurface()->resource()))
        return false;

    const auto MOUSE    = g_pInputManager->getMouseCoordsInternal();
    auto       PMONITOR = Desktop::focusState()->monitor();

    if (!PMONITOR)
        return false;

    Desktop::CViewHitTester hitTester{*Desktop::viewState()};

    const auto              WINDOWATCURSOR = hitTester.windowAt(MOUSE, Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS | Desktop::View::ALLOW_FLOATING);

    auto                    focusState = Desktop::focusState();
    auto                    window     = focusState->window();

    // windowAt() pads floating windows by the border grab area, so an upper window's
    // padding can cover this bar; it only counts when the pointer is really inside it.
    // shortcut: a third window stacked between the two isn't considered; rare with 3+ overlaps.
    // Only for a bar that is on screen: every bar sees every click, and one on another desktop
    // (or minimised) at the same spot would take it (focus it, switching desktops, or close it).
    const auto SELF        = m_pWindow.lock();
    const bool SHOWN       = SELF && SELF->mapped() && !SELF->isHidden() && SELF->m_workspace && SELF->m_workspace->visible();
    const bool PADDINGONLY = SHOWN && WINDOWATCURSOR && !realBox(WINDOWATCURSOR).containsPoint(MOUSE) && assignedBoxGlobal().containsPoint(MOUSE);
    // A hidden/minimised window can still be the focused one: its bar must not take clicks then.
    if (!SHOWN || (WINDOWATCURSOR != m_pWindow && m_pWindow != window && !PADDINGONLY))
        return false;

    PHLLS    foundSurface = nullptr;
    Vector2D surfaceCoords;

    // Check Top Layer
    hitTester.layerSurfaceAt(MOUSE, &PMONITOR->m_layerSurfaceLayers[ZWLR_LAYER_SHELL_V1_LAYER_TOP], &surfaceCoords, &foundSurface);
    if (foundSurface)
        return false;

    // Check Overlay Layer
    hitTester.layerSurfaceAt(MOUSE, &PMONITOR->m_layerSurfaceLayers[ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY], &surfaceCoords, &foundSurface);
    if (foundSurface)
        return false;

    return true;
}

void CHyprBar::onMouseButton(Event::SCallbackInfo& info, IPointer::SButtonEvent e) {
    // Finish a top-edge resize started from this bar
    if (m_bResizingThis && e.state != WL_POINTER_BUTTON_STATE_PRESSED) {
        m_bResizingThis = false;
        info.cancelled  = true;
        g_layoutManager->endDragTarget();
        announceDrag(false);
        // keep the window inside the usable area (mac_clamp_active in hypr-qol.lua);
        // the mouse binds that do this for other resizes never see this release
        Config::Supplementary::executor()->spawn("sleep 0.08 && hyprctl eval 'mac_clamp_active()'");
        return;
    }

    // A drag this bar started ends on any release, even one over a layer surface
    // (a shell panel, the dock) that inputIsValid() rejects — it used to stay stuck.
    if (m_bDraggingThis && e.state != WL_POINTER_BUTTON_STATE_PRESSED) {
        handleUpEvent(info);
        return;
    }

    if (!inputIsValid())
        return;

    if (e.state != WL_POINTER_BUTTON_STATE_PRESSED) {
        handleUpEvent(info);
        return;
    }

    // Start a top-edge resize: Hyprland's own border zone sits inside this bar
    // (it's measured from the client box) and decorations get clicks first, so
    // without this the top edge can't be resized at all.
    if (e.button == BTN_LEFT) {
        if (const auto EDGE = topResizeEdge(); EDGE != Layout::CORNER_NONE) {
            const auto PWINDOW = m_pWindow.lock();
            if (Desktop::focusState()->window() != PWINDOW)
                Desktop::focusState()->fullWindowFocus(PWINDOW, Desktop::FOCUS_REASON_CLICK);
            info.cancelled  = true;
            m_bResizingThis = true;
            g_layoutManager->beginDragTarget(PWINDOW->layoutTarget(), MBIND_RESIZE, (Layout::eRectCorner)EDGE);
            announceDrag(true);
            return;
        }
    }

    m_lastButton = e.button;
    handleDownEvent(info, std::nullopt);
}

void CHyprBar::onTouchDown(Event::SCallbackInfo& info, ITouch::SDownEvent e) {
    // Don't do anything if you're already grabbed a window with another finger
    if (!inputIsValid() || e.touchID != 0)
        return;

    handleDownEvent(info, e);
}

void CHyprBar::onTouchUp(Event::SCallbackInfo& info, ITouch::SUpEvent e) {
    if (!m_bDragPending || !m_bTouchEv || e.touchID != m_touchId)
        return;

    handleUpEvent(info);
}

void CHyprBar::onMouseMove(Vector2D coords) {
    // ensure proper redraws of button icons on hover when using hardware cursors
    if (g_pGlobalState->config.iconOnHover->value())
        damageOnButtonHover();

    // buttons_on_hover: the buttons only exist while the cursor is over the bar,
    // so the whole bar has to be redrawn as the cursor crosses its edge.
    if (g_pGlobalState->config.buttonsOnHover->value()) {
        const auto BOX     = assignedBoxGlobal();
        const auto COORDS  = cursorRelativeToBar();
        const bool HOVERED = VECINRECT(COORDS, 0, 0, BOX.w, BOX.h);
        if (HOVERED != m_bBarHovered) {
            m_bBarHovered = HOVERED;
            damageEntire();
        }
    }

    // Resize cursor on the window's real top edge (see topResizeEdge). This hook
    // runs before Hyprland's own border-cursor logic, so unsetting here never
    // clobbers the cursor Hyprland sets for the other edges.
    if (!m_bResizingThis) {
        const auto EDGE = topResizeEdge();
        if (EDGE != Layout::CORNER_NONE) {
            Pointer::Cursor::overrideController->setOverride(topEdgeCursor(EDGE), Pointer::Cursor::CURSOR_OVERRIDE_WINDOW_EDGE);
            m_bTopCursor = true;
        } else if (m_bTopCursor) {
            m_bTopCursor = false;
            Pointer::Cursor::overrideController->unsetOverride(Pointer::Cursor::CURSOR_OVERRIDE_WINDOW_EDGE);
        }
    }

    if (!m_bDragPending || m_bTouchEv || !validMapped(m_pWindow) || m_touchId != 0)
        return;

    m_bDragPending = false;
    handleMovement();
}

void CHyprBar::onTouchMove(Event::SCallbackInfo& info, ITouch::SMotionEvent e) {
    if (!m_bDragPending || !m_bTouchEv || !validMapped(m_pWindow) || e.touchID != m_touchId)
        return;

    if (!m_bDraggingThis) {
        announceDrag(true);
        // Initial setup for dragging a window.
        (void)Config::Actions::floatWindow(Config::Actions::eTogglableAction::TOGGLE_ACTION_ENABLE, m_pWindow.lock());
        // Pin it so you can change workspaces while dragging a window
        (void)Config::Actions::pinWindow(Config::Actions::eTogglableAction::TOGGLE_ACTION_ENABLE, m_pWindow.lock());

        g_layoutManager->beginDragTarget(m_pWindow.lock()->layoutTarget(), MBIND_MOVE);
        m_bDraggingThis = true;
    }
}

// The window's real top edge is the top of this bar. Treat a band reaching as far
// outside it as Hyprland's other edges do (border + extend_border_grab_area), plus
// a few px into the bar (above the traffic lights), as the top resize edge, with
// the rounded ends acting as the top corners.
uint8_t CHyprBar::topResizeEdge() {
    static auto PRESIZEONBORDER = CConfigValue<Config::INTEGER>("general:resize_on_border");
    static auto PBORDERSIZE     = CConfigValue<Config::INTEGER>("general:border_size");
    static auto PEXTEND         = CConfigValue<Config::INTEGER>("general:extend_border_grab_area");
    constexpr int INSIDE        = 5;

    const auto PWINDOW = m_pWindow.lock();
    if (!*PRESIZEONBORDER || m_hidden || !validMapped(PWINDOW) || Fullscreen::controller()->isFullscreen(PWINDOW))
        return Layout::CORNER_NONE;

    const auto MOUSE   = g_pInputManager->getMouseCoordsInternal();
    const auto BAR     = assignedBoxGlobal();
    const int  OUTSIDE = *PBORDERSIZE + *PEXTEND;
    // cheap box test first: this runs for every bar on every pointer motion
    if (MOUSE.y < BAR.y - OUTSIDE || MOUSE.y >= BAR.y + INSIDE || MOUSE.x < BAR.x - OUTSIDE || MOUSE.x > BAR.x + BAR.w + OUTSIDE)
        return Layout::CORNER_NONE;

    Desktop::CViewHitTester hitTester{*Desktop::viewState()};
    if (hitTester.windowAt(MOUSE, Desktop::View::RESERVED_EXTENTS | Desktop::View::INPUT_EXTENTS | Desktop::View::ALLOW_FLOATING) != PWINDOW)
        return Layout::CORNER_NONE;
    // The grab band outside this window can lie over a lower window's bar or surface
    // (e.g. its traffic lights): then that window gets the click, not a resize.
    if (!realBox(PWINDOW).containsPoint(MOUSE)) {
        for (const auto& w : Desktop::windowState()->windows()) {
            if (w != PWINDOW && w->mapped() && !w->isHidden() && w->m_workspace && w->m_workspace->visible() && realBox(w).containsPoint(MOUSE))
                return Layout::CORNER_NONE;
        }
    }

    const double CORNER = PWINDOW->presentation().rounding() + *PBORDERSIZE + 10;
    if (MOUSE.x < BAR.x + CORNER)
        return Layout::CORNER_TOPLEFT;
    if (MOUSE.x > BAR.x + BAR.w - CORNER)
        return Layout::CORNER_TOPRIGHT;
    return Layout::CORNER_TOP;
}

void CHyprBar::handleDownEvent(Event::SCallbackInfo& info, std::optional<ITouch::SDownEvent> touchEvent) {
    m_bTouchEv = touchEvent.has_value();
    if (m_bTouchEv)
        m_touchId = touchEvent.value().touchID;

    const auto PWINDOW = m_pWindow.lock();

    auto       COORDS = cursorRelativeToBar();
    if (m_bTouchEv) {
        ITouch::SDownEvent e        = touchEvent.value();
        PHLMONITOR         PMONITOR = nullptr;
        for (auto& m : State::monitorState()->monitors()) {
            if (m->m_name == (!e.device->m_boundOutput.empty() ? e.device->m_boundOutput : "")) {
                PMONITOR = m;
                break;
            }
        }
        PMONITOR = PMONITOR ? PMONITOR : Desktop::focusState()->monitor();
        COORDS   = Vector2D(PMONITOR->m_position.x + e.pos.x * PMONITOR->m_size.x, PMONITOR->m_position.y + e.pos.y * PMONITOR->m_size.y) - assignedBoxGlobal().pos();
    }

    const auto HEIGHT           = g_pGlobalState->config.barHeight->value();
    const auto BARBUTTONPADDING = g_pGlobalState->config.barButtonPadding->value();
    const auto BARPADDING       = g_pGlobalState->config.barPadding->value();
    const auto ALIGNBUTTONS     = g_pGlobalState->config.barButtonsAlignment->value();
    const auto ON_DOUBLE_CLICK  = g_pGlobalState->config.onDoubleClick->value();

    const bool BUTTONSRIGHT = ALIGNBUTTONS != "left";

    if (!VECINRECT(COORDS, 0, 0, assignedBoxGlobal().w, HEIGHT - 1)) {

        if (m_bDraggingThis) {
            if (m_bTouchEv)
                (void)Config::Actions::floatWindow(Config::Actions::eTogglableAction::TOGGLE_ACTION_DISABLE);
            g_layoutManager->endDragTarget();
            announceDrag(false);
            LOG(Log::DEBUG, "[hyprbars] Dragging ended on {:x}", (uintptr_t)PWINDOW.get());
        }

        m_bDraggingThis = false;
        m_bDragPending  = false;
        m_bTouchEv      = false;
        return;
    }

    // don't swallow clicks meant for xdg popups (e.g. context menus) overlapping the bar
    if (PWINDOW->hasPopupAt(COORDS + assignedBoxGlobal().pos()))
        return;

    if (Desktop::focusState()->window() != PWINDOW)
        Desktop::focusState()->fullWindowFocus(PWINDOW, Desktop::FOCUS_REASON_CLICK);

    if (PWINDOW->isFloating())
        Desktop::windowState()->raise(PWINDOW);

    info.cancelled   = true;
    m_bCancelledDown = true;

    if (doButtonPress(BARPADDING, BARBUTTONPADDING, HEIGHT, COORDS, BUTTONSRIGHT))
        return;

    if (!ON_DOUBLE_CLICK.empty() &&
        std::chrono::duration_cast<std::chrono::milliseconds>(Time::steadyNow() - m_lastMouseDown).count() < 400 /* Arbitrary delay I found suitable */) {
        Config::Supplementary::executor()->spawn(ON_DOUBLE_CLICK);
        announceClick("double");
        m_bDragPending = false;
    } else {
        m_lastMouseDown = Time::steadyNow();
        m_bDragPending  = true;
    }
}

void CHyprBar::handleUpEvent(Event::SCallbackInfo& info) {
    // A drag this bar started always ends here, focused or not: something taking focus
    // mid-drag (a window sliding under the pointer) left it stuck in move mode, and
    // macdrag>>0 never came.
    if (!m_bDraggingThis && m_pWindow.lock() != Desktop::focusState()->window())
        return;

    if (m_bCancelledDown)
        info.cancelled = true;

    m_bCancelledDown = false;

    if (m_bDraggingThis) {
        g_layoutManager->endDragTarget();
        m_bDraggingThis = false;
        announceDrag(false);
        if (m_bTouchEv)
            (void)Config::Actions::floatWindow(Config::Actions::eTogglableAction::TOGGLE_ACTION_DISABLE);

        LOG(Log::DEBUG, "[hyprbars] Dragging ended on {:x}", (uintptr_t)m_pWindow.lock().get());
    }

    // pressed and released without moving: a click (drags clear m_bDragPending on the first move)
    if (m_bDragPending && !m_bTouchEv)
        announceClick(m_lastButton == BTN_RIGHT ? "right" : "left");

    m_bDragPending = false;
    m_bTouchEv     = false;
    m_touchId      = 0;
}

void CHyprBar::handleMovement() {
    g_layoutManager->beginDragTarget(m_pWindow.lock()->layoutTarget(), MBIND_MOVE);
    m_bDraggingThis = true;
    announceDrag(true);
    LOG(Log::DEBUG, "[hyprbars] Dragging initiated on {:x}", (uintptr_t)m_pWindow.lock().get());
    return;
}

bool CHyprBar::doButtonPress(Config::INTEGER barPadding, Config::INTEGER barButtonPadding, Config::INTEGER barHeight, Vector2D COORDS, const bool BUTTONSRIGHT) {
    //check if on a button
    float offset = barPadding;

    for (auto& b : g_pGlobalState->buttons) {
        const auto BARBUF     = Vector2D{assignedBoxGlobal().w, sc<double>(barHeight)};
        Vector2D   currentPos = Vector2D{(BUTTONSRIGHT ? BARBUF.x - barButtonPadding - b.size - offset : offset), (BARBUF.y - b.size) / 2.0}.floor();

        if (VECINRECT(COORDS, currentPos.x, currentPos.y, currentPos.x + b.size + barButtonPadding, currentPos.y + b.size)) {
            // hit on close
            Config::Supplementary::executor()->spawn(b.cmd);
            return true;
        }

        offset += barButtonPadding + b.size;
    }
    return false;
}

void CHyprBar::renderBarTitle(const Vector2D& bufferSize, const float scale) {
    const auto COLORVAL         = g_pGlobalState->config.textColor->value();
    const auto SIZE             = g_pGlobalState->config.barTextSize->value();
    const auto WEIGHT           = g_pGlobalState->config.barTextWeight->value();
    const auto FONT             = g_pGlobalState->config.barTextFont->value();
    const auto ALIGN            = g_pGlobalState->config.barTextAlign->value();
    const auto BARPADDING       = g_pGlobalState->config.barPadding->value();
    const auto BARBUTTONPADDING = g_pGlobalState->config.barButtonPadding->value();

    float      buttonSizes = BARBUTTONPADDING;
    for (auto& b : g_pGlobalState->buttons) {
        buttonSizes += b.size + BARBUTTONPADDING;
    }

    const int  scaledSize        = std::round(SIZE * scale);
    const auto scaledButtonsSize = buttonSizes * scale;
    const auto scaledBarPadding  = BARPADDING * scale;
    const int  paddingTotal      = scaledBarPadding * 2 + scaledButtonsSize + (ALIGN != "left" ? scaledButtonsSize : 0);
    const int  maxWidth          = std::clamp(sc<int>(bufferSize.x - paddingTotal), 0, INT_MAX);

    if (m_szLastTitle.empty() || maxWidth < 1) {
        m_pTextTex = nullptr;
        return;
    }

    const CHyprColor COLOR = m_bForcedTitleColor.value_or(configColor(COLORVAL));
    m_pTextTex             = g_pHyprRenderer->renderText(m_szLastTitle, COLOR, scaledSize, false, FONT, maxWidth, WEIGHT.m_value);
}

size_t CHyprBar::getVisibleButtonCount(Config::INTEGER barButtonPadding, Config::INTEGER barPadding, const Vector2D& bufferSize, const float scale) {
    float  availableSpace = bufferSize.x - barPadding * scale * 2;
    size_t count          = 0;

    for (const auto& button : g_pGlobalState->buttons) {
        const float buttonSpace = (button.size + barButtonPadding) * scale;
        if (availableSpace >= buttonSpace) {
            count++;
            availableSpace -= buttonSpace;
        } else
            break;
    }

    return count;
}

void CHyprBar::renderBarButtons(Render::CRenderContext& ctx, CBox* barBox, const float scale, const float a) {
    if (g_pGlobalState->config.buttonsOnHover->value() && !m_bBarHovered)
        return;

    const auto BARBUTTONPADDING = g_pGlobalState->config.barButtonPadding->value();
    const auto BARPADDING       = g_pGlobalState->config.barPadding->value();
    const auto ALIGNBUTTONS     = g_pGlobalState->config.barButtonsAlignment->value();
    const auto INACTIVECOLOR    = g_pGlobalState->config.inactiveButtonColor->value();

    const bool BUTTONSRIGHT    = ALIGNBUTTONS != "left";
    const auto visibleCount    = getVisibleButtonCount(BARBUTTONPADDING, BARPADDING, Vector2D{barBox->w, barBox->h}, scale);
    const bool INVALIDATEICONS = m_bButtonsDirty || m_bWindowSizeChanged;

    // Use the live hover state for this frame (not last frame's), so the halo
    // and glyphs always agree with where the pointer actually is
    m_iButtonHoverState = hoverMask();

    int        offset = BARPADDING * scale;
    for (size_t i = 0; i < visibleCount; ++i) {
        auto&      button           = g_pGlobalState->buttons[i];
        const auto scaledButtonSize = button.size * scale;
        const auto scaledButtonsPad = BARBUTTONPADDING * scale;

        auto       color = button.bgcol;

        const bool GROUPHOVER  = m_iButtonHoverState > 0;
        const bool THISHOVERED = (m_iButtonHoverState & (1 << i)) != 0;

        if (INACTIVECOLOR > 0) {
            // macOS: unfocused windows show grey lights, but hovering brings the colours back
            color = (m_bWindowHasFocus || GROUPHOVER) ? color : configColor(INACTIVECOLOR);
            if (INVALIDATEICONS && button.userfg && button.iconTex)
                button.iconTex = nullptr;
        }

        color.a *= a;

        CBox buttonBox = {barBox->x + (BUTTONSRIGHT ? barBox->w - offset - scaledButtonSize : offset), barBox->y + (barBox->h - scaledButtonSize) / 2.0, scaledButtonSize,
                          scaledButtonSize};
        buttonBox.round();

        if (THISHOVERED) {
            // soft halo around the button under the pointer
            const auto HALO = std::round(3 * scale);
            CBox       haloBox = {buttonBox.x - HALO, buttonBox.y - HALO, buttonBox.w + HALO * 2, buttonBox.h + HALO * 2};
            haloBox.round();
            auto haloCol = button.bgcol;
            haloCol.a    = 0.38 * a;
            g_pHyprOpenGL->renderRect(ctx, haloBox, haloCol, {.round = static_cast<int>(std::round(haloBox.w / 2.0)), .roundingPower = 2.F});
            // and darken it slightly, like a pressed-ready macOS light
            color = CHyprColor(color.r * 0.82, color.g * 0.82, color.b * 0.82, color.a);
        }

        g_pHyprOpenGL->renderRect(ctx, buttonBox, color, {.round = sc<int>(std::round(scaledButtonSize / 2.0)), .roundingPower = 2.F});

        offset += scaledButtonsPad + scaledButtonSize;
    }
}

void CHyprBar::renderBarButtonsText(Render::CRenderContext& ctx, CBox* barBox, const float scale, const float a) {
    if (g_pGlobalState->config.buttonsOnHover->value() && !m_bBarHovered)
        return;

    const auto HEIGHT           = g_pGlobalState->config.barHeight->value();
    const auto BARBUTTONPADDING = g_pGlobalState->config.barButtonPadding->value();
    const auto BARPADDING       = g_pGlobalState->config.barPadding->value();
    const auto ALIGNBUTTONS     = g_pGlobalState->config.barButtonsAlignment->value();
    const auto ICONONHOVER      = g_pGlobalState->config.iconOnHover->value();

    const bool BUTTONSRIGHT = ALIGNBUTTONS != "left";
    const auto visibleCount = getVisibleButtonCount(BARBUTTONPADDING, BARPADDING, Vector2D{barBox->w, barBox->h}, scale);
    const auto COORDS       = cursorRelativeToBar();

    int        offset        = BARPADDING * scale;
    float      noScaleOffset = BARPADDING;

    for (size_t i = 0; i < visibleCount; ++i) {
        auto&      button           = g_pGlobalState->buttons[i];
        const auto scaledButtonSize = button.size * scale;
        const auto scaledButtonsPad = BARBUTTONPADDING * scale;

        // check if hovering here
        const auto BARBUF     = Vector2D{assignedBoxGlobal().w, sc<double>(HEIGHT)};
        Vector2D   currentPos = Vector2D{(BUTTONSRIGHT ? BARBUF.x - BARBUTTONPADDING - button.size - noScaleOffset : noScaleOffset), (BARBUF.y - button.size) / 2.0}.floor();
        bool       hovering   = VECINRECT(COORDS, currentPos.x, currentPos.y, currentPos.x + button.size + BARBUTTONPADDING, currentPos.y + button.size);
        noScaleOffset += BARBUTTONPADDING + button.size;

        const bool NEEDICON = !button.icon.empty() &&
            (!button.iconTex || button.iconTex->m_texID == 0 || !button.m_fIconScale.has_value() || std::abs(button.m_fIconScale.value_or(0.F) - scale) > 1e-6);
        if (NEEDICON) {
            // render icon
            auto fgcol = button.userfg ? button.fgcol : (button.bgcol.r + button.bgcol.g + button.bgcol.b < 1) ? CHyprColor(0xFFFFFFFF) : CHyprColor(0xFF000000);

            button.iconTex      = g_pHyprRenderer->renderText(button.icon, fgcol, std::round(button.size * 0.8 * scale), false, "sans", scaledButtonSize, 700);
            button.m_fIconScale = scale;
        }

        if (!button.iconTex || button.iconTex->m_texID == 0)
            continue;

        const auto iconX = barBox->x + (BUTTONSRIGHT ? barBox->width - offset - scaledButtonSize / 2.0 : offset + scaledButtonSize / 2.0) - button.iconTex->m_size.x / 2.0;
        const auto iconY = barBox->y + barBox->height / 2.0 - button.iconTex->m_size.y / 2.0;
        CBox       pos   = {iconX, iconY, button.iconTex->m_size.x, button.iconTex->m_size.y};
        pos.round(); // snap to whole pixels, otherwise the icon is sampled at a half-pixel offset and blurs

        if (!ICONONHOVER || (ICONONHOVER && m_iButtonHoverState > 0))
            g_pHyprOpenGL->renderTexture(ctx, button.iconTex, pos, {.a = a});
        offset += scaledButtonsPad + scaledButtonSize;

        bool currentBit = (m_iButtonHoverState & (1 << i)) != 0;
        if (hovering != currentBit) {
            m_iButtonHoverState ^= (1 << i);
            // damage to get rid of some artifacts when icons are "hidden"
            damageEntire();
        }
    }
}

void CHyprBar::draw(Render::CRenderContext& ctx, PHLMONITOR monitor, const float& a, const Render::SWindowRenderPresentation& presentation) {
    const auto ENABLED = g_pGlobalState->config.enabled->value();

    if (m_bLastEnabledState != ENABLED) {
        m_bLastEnabledState = ENABLED;
        g_pDecorationPositioner->repositionDeco(this);
    }

    if (m_hidden || !validMapped(m_pWindow) || !ENABLED)
        return;

    const auto PWINDOW = m_pWindow.lock();

    if (!PWINDOW->m_ruleApplicator->decorate().valueOrDefault())
        return;

    auto data = CBarPassElement::SBarData{this, a};
    Render::IHyprRenderer::addPassElement(ctx, makeUnique<CBarPassElement>(data));
}

void CHyprBar::renderPass(Render::CRenderContext& ctx, PHLMONITOR pMonitor, const float& a) {
    const auto  PWINDOW = m_pWindow.lock();

    static auto PENABLEBLURGLOBAL = CConfigValue<Config::BOOL>("decoration:blur:enabled");
    const auto  BARCOLOR          = g_pGlobalState->config.barColor->value();
    const auto  HEIGHT            = g_pGlobalState->config.barHeight->value();
    const auto  PRECEDENCE        = g_pGlobalState->config.barPrecedenceOverBorder->value();
    const auto  ALIGNBUTTONS      = g_pGlobalState->config.barButtonsAlignment->value();
    const auto  ENABLETITLE       = g_pGlobalState->config.barTitleEnabled->value();
    const auto  ENABLEBLUR        = g_pGlobalState->config.barBlur->value();
    const auto  INACTIVECOLOR     = g_pGlobalState->config.inactiveButtonColor->value();

    if (INACTIVECOLOR > 0) {
        bool currentWindowFocus = PWINDOW == Desktop::focusState()->window();
        if (currentWindowFocus != m_bWindowHasFocus) {
            m_bWindowHasFocus = currentWindowFocus;
            m_bButtonsDirty   = true;
        }
    }

    const CHyprColor DEST_COLOR = m_bForcedBarColor.value_or(configColor(BARCOLOR));
    if (DEST_COLOR != m_cRealBarColor->goal())
        *m_cRealBarColor = DEST_COLOR;

    CHyprColor color = m_cRealBarColor->value();

    color.a *= a;
    const bool BUTTONSRIGHT = ALIGNBUTTONS != "left";
    const bool SHOULDBLUR   = ENABLEBLUR && *PENABLEBLURGLOBAL && color.a < 1.F;

    if (HEIGHT < 1) {
        m_iLastHeight = HEIGHT;
        return;
    }

    const auto PWORKSPACE      = PWINDOW->m_workspace;
    const auto WORKSPACEOFFSET = PWORKSPACE && !(PWINDOW->m_state & Desktop::View::WINDOW_STATE_PINNED) ? PWORKSPACE->m_renderOffset->value() : Vector2D();

    const auto ROUNDING = PWINDOW->presentation().rounding() + (PRECEDENCE ? 0 : PWINDOW->presentation().borderSize());

    const auto scaledRounding = ROUNDING > 0 ? ROUNDING * pMonitor->m_scale - 2 /* idk why but otherwise it looks bad due to the gaps */ : 0;

    m_seExtents = {{0, sc<int>(HEIGHT)}, {}};

    const auto DECOBOX = assignedBoxGlobal();

    const auto BARBUF = DECOBOX.size() * pMonitor->m_scale;

    CBox       titleBarBox = {DECOBOX.x - pMonitor->m_position.x, DECOBOX.y - pMonitor->m_position.y, DECOBOX.w,
                              DECOBOX.h + ROUNDING * 3 /* to fill the bottom cuz we can't disable rounding there */};

    titleBarBox.translate(PWINDOW->presentation().floatingOffset()).scale(pMonitor->m_scale).round();

    if (titleBarBox.w < 1 || titleBarBox.h < 1)
        return;

    g_pHyprOpenGL->scissor(ctx, titleBarBox);

    if (ROUNDING) {
        // the +1 is a shit garbage temp fix until renderRect supports an alpha matte
        CBox windowBox = {PWINDOW->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT).x + PWINDOW->presentation().floatingOffset().x - pMonitor->m_position.x + 1,
                          PWINDOW->position(Desktop::View::IGeometric::GEOMETRIC_CURRENT).y + PWINDOW->presentation().floatingOffset().y - pMonitor->m_position.y + 1,
                          PWINDOW->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT).x - 2, PWINDOW->size(Desktop::View::IGeometric::GEOMETRIC_CURRENT).y - 2};

        if (windowBox.w < 1 || windowBox.h < 1)
            return;

        glClearStencil(0);
        glClear(GL_STENCIL_BUFFER_BIT);

        g_pHyprOpenGL->setCapStatus(GL_STENCIL_TEST, true);

        glStencilFunc(GL_ALWAYS, 1, -1);
        glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE);

        glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);

        windowBox.translate(WORKSPACEOFFSET).scale(pMonitor->m_scale).round();
        g_pHyprOpenGL->renderRect(ctx, windowBox, CHyprColor(0, 0, 0, 0),
                                  CHyprOpenGLImpl::SRectRenderData{.round = sc<int>(scaledRounding), .roundingPower = m_pWindow->presentation().roundingPower()});
        glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);

        glStencilFunc(GL_NOTEQUAL, 1, -1);
        glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE);
    }

    if (SHOULDBLUR)
        g_pHyprOpenGL->renderRect(
            ctx, titleBarBox, color,
            CHyprOpenGLImpl::SRectRenderData{.round = sc<int>(scaledRounding), .roundingPower = m_pWindow->presentation().roundingPower(), .blur = true, .blurA = a});
    else
        g_pHyprOpenGL->renderRect(ctx, titleBarBox, color,
                                  CHyprOpenGLImpl::SRectRenderData{.round = sc<int>(scaledRounding), .roundingPower = m_pWindow->presentation().roundingPower()});

    // render title
    const int  SCALEDTEXTSIZE = std::round(g_pGlobalState->config.barTextSize->value() * pMonitor->m_scale);
    const auto TITLE          = m_forcedTitle.value_or(PWINDOW->metadata().title());
    if (ENABLETITLE &&
        (m_szLastTitle != TITLE || m_bWindowSizeChanged || !m_pTextTex || m_pTextTex->m_texID == 0 || m_bTitleColorChanged || m_iLastScaledTextSize != SCALEDTEXTSIZE)) {
        m_szLastTitle = TITLE;
        renderBarTitle(BARBUF, pMonitor->m_scale);
        m_iLastScaledTextSize = SCALEDTEXTSIZE;
    }

    if (ROUNDING) {
        // cleanup stencil
        glClearStencil(0);
        glClear(GL_STENCIL_BUFFER_BIT);
        g_pHyprOpenGL->setCapStatus(GL_STENCIL_TEST, false);
        glStencilMask(-1);
        glStencilFunc(GL_ALWAYS, 1, 0xFF);
    }

    CBox textBox = {titleBarBox.x, titleBarBox.y, BARBUF.x, BARBUF.y};
    if (ENABLETITLE && m_pTextTex) {
        const auto BARPADDING       = g_pGlobalState->config.barPadding->value();
        const auto BARBUTTONPADDING = g_pGlobalState->config.barButtonPadding->value();
        const auto ALIGN            = g_pGlobalState->config.barTextAlign->value();

        float      buttonSizes = BARBUTTONPADDING;
        for (auto& b : g_pGlobalState->buttons) {
            buttonSizes += b.size + BARBUTTONPADDING;
        }

        const auto scaledBorderSize  = PWINDOW->presentation().borderSize() * pMonitor->m_scale;
        const auto scaledButtonsSize = buttonSizes * pMonitor->m_scale;
        const auto scaledBarPadding  = BARPADDING * pMonitor->m_scale;
        const auto xOffset           = ALIGN == "left" ? std::round(scaledBarPadding + (BUTTONSRIGHT ? 0 : scaledButtonsSize)) :
                                                         std::round(((BARBUF.x - scaledBorderSize) / 2.0 - m_pTextTex->m_size.x / 2.0));
        const auto yOffset           = std::round((BARBUF.y - m_pTextTex->m_size.y) / 2.0);
        CBox       titleBox          = {textBox.x + xOffset, textBox.y + yOffset, m_pTextTex->m_size.x, m_pTextTex->m_size.y};

        g_pHyprOpenGL->renderTexture(ctx, m_pTextTex, titleBox, {.a = a});
    }

    renderBarButtons(ctx, &textBox, pMonitor->m_scale, a);
    m_bButtonsDirty = false;

    g_pHyprOpenGL->scissor(ctx, nullptr);

    renderBarButtonsText(ctx, &textBox, pMonitor->m_scale, a);

    m_bWindowSizeChanged = false;
    m_bTitleColorChanged = false;

    // dynamic updates change the extents
    if (m_iLastHeight != HEIGHT) {
        PWINDOW->layoutTarget()->recalc();
        m_iLastHeight = HEIGHT;
    }
}

eDecorationType CHyprBar::getDecorationType() {
    return DECORATION_CUSTOM;
}

void CHyprBar::updateWindow(PHLWINDOW pWindow) {
    damageEntire();
}

void CHyprBar::onConfigReloaded() {
    m_bButtonsDirty      = true;
    m_bTitleColorChanged = true;
    m_pTextTex           = nullptr;

    g_pDecorationPositioner->repositionDeco(this);
    damageEntire();
}

void CHyprBar::damageEntire() {
    g_pHyprRenderer->damageBox(assignedBoxGlobal());
}

Vector2D CHyprBar::cursorRelativeToBar() {
    return g_pInputManager->getMouseCoordsInternal() - assignedBoxGlobal().pos();
}

eDecorationLayer CHyprBar::getDecorationLayer() {
    return DECORATION_LAYER_UNDER;
}

uint64_t CHyprBar::getDecorationFlags() {
    return DECORATION_ALLOWS_MOUSE_INPUT | (g_pGlobalState->config.barPartOfWindow->value() ? DECORATION_PART_OF_MAIN_WINDOW : 0);
}

CBox CHyprBar::assignedBoxGlobal() {
    if (!validMapped(m_pWindow))
        return {};

    CBox box = m_bAssignedBox;
    box.translate(g_pDecorationPositioner->getEdgeDefinedPoint(DECORATION_EDGE_TOP, m_pWindow.lock()));

    const auto PWORKSPACE      = m_pWindow->m_workspace;
    const auto WORKSPACEOFFSET = PWORKSPACE && !(m_pWindow->m_state & Desktop::View::WINDOW_STATE_PINNED) ? PWORKSPACE->m_renderOffset->value() : Vector2D();

    return box.translate(WORKSPACEOFFSET);
}

PHLWINDOW CHyprBar::getOwner() {
    return m_pWindow.lock();
}

void CHyprBar::setTitle(std::optional<std::string> title) {
    m_forcedTitle = std::move(title);
    damageEntire();
}

void CHyprBar::updateRules() {
    const auto PWINDOW              = m_pWindow.lock();
    auto       prevHidden           = m_hidden;
    auto       prevForcedTitleColor = m_bForcedTitleColor;

    m_bForcedBarColor   = std::nullopt;
    m_bForcedTitleColor = std::nullopt;
    m_hidden            = false;

    if (PWINDOW->m_ruleApplicator->m_otherProps.props.contains(g_pGlobalState->nobarRuleIdx))
        m_hidden = truthy(PWINDOW->m_ruleApplicator->m_otherProps.props.at(g_pGlobalState->nobarRuleIdx)->effect);
    if (PWINDOW->m_ruleApplicator->m_otherProps.props.contains(g_pGlobalState->barColorRuleIdx))
        m_bForcedBarColor = CHyprColor(Config::ParserUtils::parseColor(PWINDOW->m_ruleApplicator->m_otherProps.props.at(g_pGlobalState->barColorRuleIdx)->effect).value_or(0));
    if (PWINDOW->m_ruleApplicator->m_otherProps.props.contains(g_pGlobalState->titleColorRuleIdx))
        m_bForcedTitleColor = CHyprColor(Config::ParserUtils::parseColor(PWINDOW->m_ruleApplicator->m_otherProps.props.at(g_pGlobalState->titleColorRuleIdx)->effect).value_or(0));

    if (prevHidden != m_hidden)
        g_pDecorationPositioner->repositionDeco(this);
    if (prevForcedTitleColor != m_bForcedTitleColor)
        m_bTitleColorChanged = true;
}

uint32_t CHyprBar::hoverMask() {
    const auto BARPADDING       = g_pGlobalState->config.barPadding->value();
    const auto BARBUTTONPADDING = g_pGlobalState->config.barButtonPadding->value();
    const auto HEIGHT           = g_pGlobalState->config.barHeight->value();
    const auto ALIGNBUTTONS     = g_pGlobalState->config.barButtonsAlignment->value();
    const bool BUTTONSRIGHT     = ALIGNBUTTONS != "left";
    const auto COORDS           = cursorRelativeToBar();

    float      offset = BARPADDING;
    uint32_t   mask   = 0;
    size_t     i      = 0;
    for (auto& b : g_pGlobalState->buttons) {
        const auto BARBUF     = Vector2D{assignedBoxGlobal().w, sc<double>(HEIGHT)};
        Vector2D   currentPos = Vector2D{(BUTTONSRIGHT ? BARBUF.x - BARBUTTONPADDING - b.size - offset : offset), (BARBUF.y - b.size) / 2.0}.floor();
        if (VECINRECT(COORDS, currentPos.x, currentPos.y, currentPos.x + b.size + BARBUTTONPADDING, currentPos.y + b.size))
            mask |= (1u << i);
        offset += BARBUTTONPADDING + b.size;
        ++i;
    }
    return mask;
}

void CHyprBar::damageOnButtonHover() {
    // Per-button hover tracking so moving between buttons redraws the halo
    const uint32_t mask = hoverMask();
    if (mask != m_iLastHoverMask) {
        m_iLastHoverMask = mask;
        m_bButtonHovered = mask != 0;
        damageEntire();
    }
}

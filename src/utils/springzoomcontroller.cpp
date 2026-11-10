// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#include "springzoomcontroller.h"

#include <algorithm>
#include <cmath>

namespace kdockw
{

namespace
{
constexpr qreal kMaximumElapsedSeconds = 0.1;
constexpr qreal kMaximumStepSeconds = 1.0 / 240.0;
constexpr qreal kSettlePositionEpsilon = 0.001;
constexpr qreal kSettleVelocityEpsilon = 0.01;
}

SpringZoomController::SpringZoomController(QObject *parent)
    : QObject(parent)
{
    m_timer.setInterval(5);
    m_timer.setTimerType(Qt::PreciseTimer);
    connect(&m_timer, &QTimer::timeout, this, &SpringZoomController::tick);
}

qreal SpringZoomController::cursor() const
{
    return m_cursor.value;
}

qreal SpringZoomController::amount() const
{
    return m_amount.value;
}

void SpringZoomController::setTarget(qreal cursorValue,
                                     qreal amountValue,
                                     qreal stiffness,
                                     qreal damping,
                                     qreal speed,
                                     qreal cursorMinimum,
                                     qreal cursorMaximum)
{
    const qreal safeMinimum = std::min(cursorMinimum, cursorMaximum);
    const qreal safeMaximum = std::max(cursorMinimum, cursorMaximum);
    m_cursorMinimum = safeMinimum;
    m_cursorMaximum = safeMaximum;
    m_cursor.target = std::clamp(cursorValue, safeMinimum, safeMaximum);
    m_amount.target = std::clamp(amountValue, 0.0, 1.0);
    m_stiffness = std::clamp(stiffness, 20.0, 500.0);
    m_damping = std::clamp(damping, 0.2, 1.5);
    m_speed = std::clamp(speed, 0.25, 3.0);
    startIfNeeded();
}

void SpringZoomController::synchronize(qreal cursorValue, qreal amountValue)
{
    // The first live cursor can arrive before the target bounds have been
    // supplied. Preserve it exactly so enabling Spring does not sweep from 0.
    m_cursorMinimum = std::min(m_cursorMinimum, cursorValue);
    m_cursorMaximum = std::max(m_cursorMaximum, cursorValue);
    const qreal cursor = cursorValue;
    const qreal amount = std::clamp(amountValue, 0.0, 1.0);
    const bool changed = !qFuzzyCompare(m_cursor.value + 1.0, cursor + 1.0)
        || !qFuzzyCompare(m_amount.value + 1.0, amount + 1.0)
        || !qFuzzyIsNull(m_cursor.velocity) || !qFuzzyIsNull(m_amount.velocity);
    m_cursor = {cursor, 0.0, cursor};
    m_amount = {amount, 0.0, amount};
    m_timer.stop();
    if (changed) {
        Q_EMIT stateChanged();
    }
}

void SpringZoomController::synchronizeCursor(qreal cursorValue,
                                             qreal cursorMinimum,
                                             qreal cursorMaximum)
{
    const qreal safeMinimum = std::min(cursorMinimum, cursorMaximum);
    const qreal safeMaximum = std::max(cursorMinimum, cursorMaximum);
    m_cursorMinimum = safeMinimum;
    m_cursorMaximum = safeMaximum;
    const qreal cursor = std::clamp(cursorValue, safeMinimum, safeMaximum);
    const bool changed = !qFuzzyCompare(m_cursor.value + 1.0, cursor + 1.0)
        || !qFuzzyCompare(m_cursor.target + 1.0, cursor + 1.0)
        || !qFuzzyIsNull(m_cursor.velocity);
    m_cursor = {cursor, 0.0, cursor};
    if (changed) {
        Q_EMIT stateChanged();
    }
    startIfNeeded();
}

void SpringZoomController::advance(qreal elapsedSeconds)
{
    const qreal elapsed = std::clamp(elapsedSeconds, 0.0, kMaximumElapsedSeconds);
    if (elapsed <= 0.0 || settled()) {
        return;
    }

    const qreal effectiveStiffness = m_stiffness * m_speed * m_speed;
    const qreal dampingRatio = m_damping;
    const int steps = std::max(1, static_cast<int>(std::ceil(elapsed / kMaximumStepSeconds)));
    const qreal step = elapsed / steps;
    for (int i = 0; i < steps; ++i) {
        integrate(m_cursor, step, effectiveStiffness, dampingRatio);
        integrate(m_amount, step, effectiveStiffness, dampingRatio);

        if (m_cursor.value < m_cursorMinimum) {
            m_cursor.value = m_cursorMinimum;
            m_cursor.velocity = std::max(0.0, m_cursor.velocity);
        } else if (m_cursor.value > m_cursorMaximum) {
            m_cursor.value = m_cursorMaximum;
            m_cursor.velocity = std::min(0.0, m_cursor.velocity);
        }
        if (m_amount.value < 0.0) {
            m_amount.value = 0.0;
            m_amount.velocity = std::max(0.0, m_amount.velocity);
        } else if (m_amount.value > 1.0) {
            m_amount.value = 1.0;
            m_amount.velocity = std::min(0.0, m_amount.velocity);
        }
    }

    if (settled()) {
        m_cursor.value = m_cursor.target;
        m_cursor.velocity = 0.0;
        m_amount.value = m_amount.target;
        m_amount.velocity = 0.0;
        m_timer.stop();
    }
    Q_EMIT stateChanged();
}

bool SpringZoomController::settled() const
{
    return std::abs(m_cursor.target - m_cursor.value) <= kSettlePositionEpsilon
        && std::abs(m_cursor.velocity) <= kSettleVelocityEpsilon
        && std::abs(m_amount.target - m_amount.value) <= kSettlePositionEpsilon
        && std::abs(m_amount.velocity) <= kSettleVelocityEpsilon;
}

void SpringZoomController::integrate(Axis &axis, qreal dt, qreal stiffness, qreal dampingRatio)
{
    // Semi-implicit Euler on a normalized second-order spring. The bounded
    // substep makes the result stable while still integrating measured time.
    const qreal damping = 2.0 * dampingRatio * std::sqrt(stiffness);
    const qreal acceleration = stiffness * (axis.target - axis.value) - damping * axis.velocity;
    axis.velocity += acceleration * dt;
    axis.value += axis.velocity * dt;
}

void SpringZoomController::startIfNeeded()
{
    if (settled()) {
        m_cursor.value = m_cursor.target;
        m_cursor.velocity = 0.0;
        m_amount.value = m_amount.target;
        m_amount.velocity = 0.0;
        m_timer.stop();
        return;
    }
    if (!m_timer.isActive()) {
        m_elapsed.start();
        m_timer.start();
    }
}

void SpringZoomController::tick()
{
    const qreal elapsed = m_elapsed.isValid() ? m_elapsed.restart() / 1000.0 : 0.0;
    advance(elapsed);
}

} // namespace kdockw

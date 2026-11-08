// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 KDockW Contributors

#pragma once

#include <QObject>
#include <QElapsedTimer>
#include <QTimer>

namespace kdockw
{

/**
 * Time-based, critically damped-capable spring follower for dock magnification.
 * The cursor and zoom amplitude share the same integrator in the live dock and
 * in the settings preview. advance() is public so unit tests can simulate
 * different refresh rates without relying on wall-clock sleeps.
 */
class SpringZoomController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(qreal cursor READ cursor NOTIFY stateChanged)
    Q_PROPERTY(qreal amount READ amount NOTIFY stateChanged)

public:
    explicit SpringZoomController(QObject *parent = nullptr);

    [[nodiscard]] qreal cursor() const;
    [[nodiscard]] qreal amount() const;

    /// Update the target while preserving velocity and current position.
    Q_INVOKABLE void setTarget(qreal cursor,
                               qreal amount,
                               qreal stiffness,
                               qreal damping,
                               qreal speed,
                               qreal cursorMinimum,
                               qreal cursorMaximum);

    /// Set a starting state without animation (used when enabling Spring).
    Q_INVOKABLE void synchronize(qreal cursor, qreal amount);

    /// Advance by measured elapsed seconds. Internally clamps elapsed time and
    /// subdivides it into bounded steps for stable integration after stalls.
    void advance(qreal elapsedSeconds);

    [[nodiscard]] bool settled() const;

Q_SIGNALS:
    void stateChanged();

private Q_SLOTS:
    void tick();

private:
    struct Axis {
        qreal value = 0.0;
        qreal velocity = 0.0;
        qreal target = 0.0;
    };

    static void integrate(Axis &axis, qreal dt, qreal stiffness, qreal dampingRatio);
    void startIfNeeded();

    QTimer m_timer;
    QElapsedTimer m_elapsed;
    Axis m_cursor;
    Axis m_amount;
    // Set from DockSettings before advancing; keep defaults in KConfigXT only.
    qreal m_stiffness = 0.0;
    qreal m_damping = 0.0;
    qreal m_speed = 0.0;
    qreal m_cursorMinimum = 0.0;
    qreal m_cursorMaximum = 0.0;
};

} // namespace kdockw

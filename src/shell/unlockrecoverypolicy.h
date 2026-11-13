// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2026 Krema Contributors

#pragma once

#include <QRect>
#include <QSize>

#include <optional>

namespace kdockw
{

/** The parts of a dock surface configuration that require Layer Shell recovery. */
struct UnlockRecoveryState
{
    quintptr screenIdentity = 0;
    QRect screenGeometry;
    QSize windowSize;
    QSize layerSize;
    int edge = 0;
    int platformEdge = 0;
    int requestedExclusiveZone = 0;
    int windowGap = 0;
    bool reserveScreenSpace = false;
    int margin = 0;
    int visibilityMode = -1;

    [[nodiscard]] bool operator==(const UnlockRecoveryState &) const = default;
};

/** Decides whether an unlock still needs the legacy surface recreation path. */
class UnlockRecoveryPolicy
{
public:
    enum class Decision {
        NoLockSnapshot,
        Unchanged,
        Changed,
    };

    void remember(const UnlockRecoveryState &state)
    {
        if (!m_lockedState) {
            m_lockedState = state;
        }
    }

    [[nodiscard]] Decision consume(const UnlockRecoveryState &state)
    {
        if (!m_lockedState) {
            return Decision::NoLockSnapshot;
        }
        const bool unchanged = *m_lockedState == state;
        m_lockedState.reset();
        return unchanged ? Decision::Unchanged : Decision::Changed;
    }

private:
    std::optional<UnlockRecoveryState> m_lockedState;
};

} // namespace kdockw

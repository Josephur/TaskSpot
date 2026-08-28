/*
    SPDX-FileCopyrightText: 2013 Sebastian Kügler <sebas@kde.org>
    SPDX-FileCopyrightText: 2014 Martin Gräßlin <mgraesslin@kde.org>
    SPDX-FileCopyrightText: 2016 Kai Uwe Broulik <kde@privat.broulik.de>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick

MouseArea {
    required property /*QModelIndex*/var modelIndex
    required property /*undefined|WId where WId = int|string*/ var winId
    required property Task rootTask

    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    hoverEnabled: true
    enabled: winId !== undefined

    // TaskSpot #14: emitted when the window card is activated with the
    // left button; the search popup listens to record a completed search.
    // Stock tooltip usage leaves it unlistened.
    signal cardActivated()

    onClicked: (mouse) => {
        switch (mouse.button) {
        case Qt.LeftButton:
            cardActivated();
            tasksModel.requestActivate(modelIndex);
            rootTask.hideImmediately();
            tasks.cancelHighlightWindows();
            break;
        case Qt.MiddleButton:
            tasks.cancelHighlightWindows();
            tasksModel.requestClose(modelIndex);
            break;
        case Qt.RightButton:
            tasks.createContextMenu(rootTask, modelIndex).show();
            break;
        }
    }

    onContainsMouseChanged: {
        tasks.windowsHovered([String(winId)], containsMouse);
    }
}

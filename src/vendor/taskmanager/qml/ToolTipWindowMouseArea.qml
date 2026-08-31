/*
    SPDX-FileCopyrightText: 2013 Sebastian Kügler <sebas@kde.org>
    SPDX-FileCopyrightText: 2014 Martin Gräßlin <mgraesslin@kde.org>
    SPDX-FileCopyrightText: 2016 Kai Uwe Broulik <kde@privat.broulik.de>

    SPDX-License-Identifier: LGPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.extras as PlasmaExtras

MouseArea {
    id: cardMouseArea

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
        case Qt.RightButton: {
            // TaskSpot #19: when the card lives in the search popup, the
            // click surface is the popup window, not the panel. The menu's
            // Wayland transient parent comes from its QML object parent's
            // window (QMenuProxy::openInternal), so without this override
            // the menu is a panel popup while the grab is on the popup
            // surface and KWin dismisses it instantly. The popup's dismissal
            // paths pause while the menu is open.
            //
            // TaskSpot #20: visualParent is the CARD, so openRelative()
            // anchors the menu at the clicked card — with the panel task
            // as visualParent the menu popped up over the taskbar button,
            // far away from the card on a near-full-width popup. The menu's
            // actions still target the task through ContextMenu's
            // taskItem, and minimumWidth mirrors a panel-task menu (the
            // card itself spans the whole popup width).
            const popup = tasks.searchPopup;
            const menu = tasks.createContextMenu(rootTask, modelIndex,
                popup ? {
                    parentItem: cardMouseArea,
                    visualParent: cardMouseArea,
                    taskItem: rootTask,
                    minimumWidth: rootTask.width,
                } : {});
            if (popup) {
                popup.menuOpen = true;
                menu.statusChanged.connect(() => {
                    if (menu.status !== PlasmaExtras.Menu.Open) {
                        popup.menuOpen = false;
                    }
                });
            }
            menu.show();
            break;
        }
        }
    }

    onContainsMouseChanged: {
        tasks.windowsHovered([String(winId)], containsMouse);
    }
}

# SPDX-License-Identifier: GPL-2.0-or-later
# TaskSpot's applet package (#18): since TaskSpot has its own plugin id,
# plasmashell loads it as a normal (KPackage + C++) applet — the package
# carries the identity and the UI QML on disk; the compiled plugin provides
# the C++ QML types and the TaskTools/LayoutMetrics JS libraries through its
# embedded QML module. QML and config sources live in src/vendor/taskmanager
# and are installed into the package from there — single source of truth,
# nothing is duplicated in git.

set(TASKSPOT_ID com.stack-tech.plasma.taskspot)
set(TASKSPOT_PKG ${CMAKE_CURRENT_SOURCE_DIR}/${TASKSPOT_ID})
set(TASKSPOT_VENDOR ${CMAKE_SOURCE_DIR}/src/vendor/taskmanager)

install(FILES ${TASKSPOT_PKG}/metadata.json
        DESTINATION ${KDE_INSTALL_DATADIR}/plasma/plasmoids/${TASKSPOT_ID})

install(FILES
            ${TASKSPOT_VENDOR}/qml/AudioStream.qml
            ${TASKSPOT_VENDOR}/qml/ConfigAppearance.qml
            ${TASKSPOT_VENDOR}/qml/ConfigBehavior.qml
            ${TASKSPOT_VENDOR}/qml/config.qml
            ${TASKSPOT_VENDOR}/qml/ContextMenu.qml
            ${TASKSPOT_VENDOR}/qml/GroupDialog.qml
            ${TASKSPOT_VENDOR}/qml/GroupExpanderOverlay.qml
            ${TASKSPOT_VENDOR}/qml/main.qml
            ${TASKSPOT_VENDOR}/qml/MouseHandler.qml
            ${TASKSPOT_VENDOR}/qml/PipeWireThumbnail.qml
            ${TASKSPOT_VENDOR}/qml/PlayerController.qml
            ${TASKSPOT_VENDOR}/qml/PulseAudio.qml
            ${TASKSPOT_VENDOR}/qml/ScrollableTextWrapper.qml
            ${TASKSPOT_VENDOR}/qml/SearchPopup.qml
            ${TASKSPOT_VENDOR}/qml/TaskBadgeOverlay.qml
            ${TASKSPOT_VENDOR}/qml/TaskList.qml
            ${TASKSPOT_VENDOR}/qml/TaskProgressOverlay.qml
            ${TASKSPOT_VENDOR}/qml/Task.qml
            ${TASKSPOT_VENDOR}/qml/ToolTipDelegate.qml
            ${TASKSPOT_VENDOR}/qml/ToolTipInstance.qml
            ${TASKSPOT_VENDOR}/qml/ToolTipWindowMouseArea.qml
        DESTINATION ${KDE_INSTALL_DATADIR}/plasma/plasmoids/${TASKSPOT_ID}/contents/ui)

install(FILES ${TASKSPOT_VENDOR}/main.xml
        DESTINATION ${KDE_INSTALL_DATADIR}/plasma/plasmoids/${TASKSPOT_ID}/contents/config)

# SPDX-License-Identifier: GPL-2.0-or-later
# TaskSpot's applet packages (#18): since TaskSpot has its own plugin id,
# plasmashell loads it as a normal (KPackage + C++) applet — the package
# carries the identity and the UI QML on disk; the compiled plugin provides
# the C++ QML types and the TaskTools/LayoutMetrics JS libraries through its
# embedded QML module. QML and config sources live in src/vendor/taskmanager
# and are installed into the package from there — single source of truth,
# nothing is duplicated in git.
#
# TaskSpot (#24): two packages share the one plugin and the vendored source
# tree — the icons-and-text widget and the icons-only variant. The
# icons-only package (com.stack-tech.plasma.taskspot.icontasks) binds the
# same .so through X-Plasma-RootPath in its metadata, the stock
# org.kde.plasma.icontasks pattern. Unlike stock (whose UI is qrc-embedded
# in the root plugin), our disk-based UI means each package must carry the
# full contents, so the same file lists install into both.

set(TASKSPOT_ID com.stack-tech.plasma.taskspot)
set(TASKSPOT_ICONS_ONLY_ID com.stack-tech.plasma.taskspot.icontasks)
set(TASKSPOT_PKG ${CMAKE_CURRENT_SOURCE_DIR})
set(TASKSPOT_VENDOR ${CMAKE_SOURCE_DIR}/src/vendor/taskmanager)

foreach(TASKSPOT_PKG_ID ${TASKSPOT_ID} ${TASKSPOT_ICONS_ONLY_ID})

install(FILES ${TASKSPOT_PKG}/${TASKSPOT_PKG_ID}/metadata.json
        DESTINATION ${KDE_INSTALL_DATADIR}/plasma/plasmoids/${TASKSPOT_PKG_ID})

install(FILES
            ${TASKSPOT_VENDOR}/qml/AudioStream.qml
            ${TASKSPOT_VENDOR}/qml/ConfigAppearance.qml
            ${TASKSPOT_VENDOR}/qml/ConfigBehavior.qml
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
        DESTINATION ${KDE_INSTALL_DATADIR}/plasma/plasmoids/${TASKSPOT_PKG_ID}/contents/ui)

# TaskSpot (#23): the config-dialog page list is a package-structure file,
# NOT UI QML. For a disk-based package Plasma::Applet::configModel() serves
# it from contents/config/config.qml (the "configmodel" file definition in
# libplasma's plasma_applet_packagestructure.cpp). Upstream taskmanager
# never hits this because plasma_add_applet embeds the file in the plugin's
# qrc, where configModel() has a separate lookup branch. Installing it to
# contents/ui/ left "Configure TaskSpot…" with zero settings pages.
install(FILES ${TASKSPOT_VENDOR}/qml/config.qml
        DESTINATION ${KDE_INSTALL_DATADIR}/plasma/plasmoids/${TASKSPOT_PKG_ID}/contents/config)

install(FILES ${TASKSPOT_VENDOR}/main.xml
        DESTINATION ${KDE_INSTALL_DATADIR}/plasma/plasmoids/${TASKSPOT_PKG_ID}/contents/config)

endforeach()

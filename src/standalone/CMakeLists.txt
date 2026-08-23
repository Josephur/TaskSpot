# SPDX-License-Identifier: GPL-2.0-or-later
# TaskSpot standalone widget artifact: a distinct applet ID (org.kde.taskspot)
# that shares the vendored taskmanager sources with the same-ID override
# artifact, so both stay behaviorally identical.

add_definitions(-DTRANSLATION_DOMAIN=\"plasma_applet_org.kde.plasma.taskmanager\")

set(TASKSPOT_VENDOR_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../vendor/taskmanager)

# The vendored QML imports its original compiled module URI. The standalone
# compiles under plasma.applet.org.kde.taskspot, so generate rewritten
# copies of every QML file for this target.
set(TASKSPOT_QML_NAMES
    AudioStream.qml
    ConfigAppearance.qml
    ConfigBehavior.qml
    config.qml
    ContextMenu.qml
    GroupDialog.qml
    GroupExpanderOverlay.qml
    main.qml
    MouseHandler.qml
    PipeWireThumbnail.qml
    PlayerController.qml
    PulseAudio.qml
    ScrollableTextWrapper.qml
    TaskBadgeOverlay.qml
    TaskList.qml
    TaskProgressOverlay.qml
    Task.qml
    ToolTipDelegate.qml
    ToolTipInstance.qml
    ToolTipWindowMouseArea.qml)
set(TASKSPOT_GENERATED_QML_SOURCES "")
foreach(name ${TASKSPOT_QML_NAMES})
    file(READ ${TASKSPOT_VENDOR_DIR}/qml/${name} content)
    string(REPLACE "plasma.applet.org.kde.plasma.taskmanager"
                   "plasma.applet.org.kde.taskspot" content "${content}")
    file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/qml/${name} "${content}")
    list(APPEND TASKSPOT_GENERATED_QML_SOURCES ${CMAKE_CURRENT_BINARY_DIR}/qml/${name})
endforeach()
foreach(name LayoutMetrics.js TaskTools.js)
    configure_file(${TASKSPOT_VENDOR_DIR}/qml/code/${name}
                   ${CMAKE_CURRENT_BINARY_DIR}/qml/code/${name} COPYONLY)
    list(APPEND TASKSPOT_GENERATED_QML_SOURCES ${CMAKE_CURRENT_BINARY_DIR}/qml/code/${name})
endforeach()

plasma_add_applet(org.kde.taskspot
    QML_SOURCES
        ${TASKSPOT_GENERATED_QML_SOURCES}
    CPP_SOURCES
        ${TASKSPOT_VENDOR_DIR}/backend.cpp
        ${TASKSPOT_VENDOR_DIR}/smartlauncherbackend.cpp
        ${TASKSPOT_VENDOR_DIR}/smartlauncheritem.cpp
    RESOURCES
        ${TASKSPOT_VENDOR_DIR}/main.xml
    GENERATE_APPLET_CLASS
)

kconfig_add_kcfg_files(org.kde.taskspot ${TASKSPOT_VENDOR_DIR}/kactivitymanagerd_plugins_settings.kcfgc)

# Generated QML type registration includes <backend.h> if reachable.
target_include_directories(org.kde.taskspot PRIVATE ${TASKSPOT_VENDOR_DIR})

ecm_qt_declare_logging_category(org.kde.taskspot
    HEADER log_settings.h
    IDENTIFIER TASKMANAGER_DEBUG
    CATEGORY_NAME org.kde.plasma.taskmanager)

target_link_libraries(org.kde.taskspot PRIVATE
                      Qt::Core
                      Qt::Qml
                      Qt::Quick
                      Plasma::Activities
                      Plasma::ActivitiesStats
                      KF6::ConfigGui
                      KF6::I18n
                      KF6::KIOCore
                      KF6::KIOGui
                      KF6::KIOFileWidgets # KFilePlacesModel
                      KF6::Notifications # KNotificationJobUiDelegate
                      Plasma::Plasma
                      KSysGuard::ProcessCore
                      KF6::Service
                      KF6::WindowSystem
                      PW::LibNotificationManager)

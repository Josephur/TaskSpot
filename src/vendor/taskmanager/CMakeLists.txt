# SPDX-License-Identifier: GPL-2.0-or-later
# Vendored from plasma-desktop applets/taskmanager (KDE), Plasma 6.7.5
# Modified by TaskSpot - see repository history for the patch series.
#
# The target below replicates plasma_add_applet()
# (/usr/lib/cmake/Plasma/PlasmaMacros.cmake, GENERATE_APPLET_CLASS branch)
# with one delta: the macro derives the QML module URI from the target id
# (plasma.applet.${id}), and the approved applet id contains a dash, which
# a QML module URI cannot express (every dot-separated URI segment must be
# a valid JS identifier). The URI therefore uses an underscore spelling
# while the target, .so name and metadata keep the approved id verbatim.
# See #18 and docs/superpowers/specs/2026-08-28-plugin-id-migration-design.md.

add_definitions(-DTRANSLATION_DOMAIN=\"plasma_applet_com.stack-tech.plasma.taskspot\")

set(TASKSPOT_ID com.stack-tech.plasma.taskspot)
set(TASKSPOT_URI plasma.applet.com.stack_tech.plasma.taskspot)

add_library(${TASKSPOT_ID} SHARED)

set_target_properties(${TASKSPOT_ID} PROPERTIES PREFIX "")

include(ECMQmlModule)
ecm_add_qml_module(${TASKSPOT_ID} URI ${TASKSPOT_URI} QT_NO_PLUGIN)

# The QML module inside the plugin carries the C++ QML types and the two
# JS libraries (TaskTools, LayoutMetrics), which QML accesses through the
# import alias. The UI QML files are NOT part of the module: the applet
# ships a regular plasmoid package (see src/packages/) whose contents/ui is
# what plasmashell actually loads — qrcPath() derives from the dashed
# plugin id, so it can never reach this module's underscored qrc path
# anyway (#18).
ecm_target_qml_sources(${TASKSPOT_ID}
    SOURCES
        qml/code/LayoutMetrics.js
        qml/code/TaskTools.js
)

set_target_properties(${TASKSPOT_ID} PROPERTIES LIBRARY_OUTPUT_DIRECTORY "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}/plasma/applets")

# Generated applet class, exactly as plasma_add_applet(GENERATE_APPLET_CLASS)
# would emit for this id.
file(GENERATE OUTPUT ${TASKSPOT_ID}.cpp CONTENT "\
#include <KPluginFactory>
#include <Plasma/Applet>

class com_stack_tech_plasma_taskspot_Plugin : public Plasma::Applet {
   Q_OBJECT
public:
   com_stack_tech_plasma_taskspot_Plugin(QObject *parent, const KPluginMetaData &data, const QVariantList &args)
      : Plasma::Applet(parent, data, args) {}
};

K_PLUGIN_CLASS_WITH_JSON(com_stack_tech_plasma_taskspot_Plugin, \"metadata.json\")

#include \"com.stack-tech.plasma.taskspot.moc\"
")

target_sources(${TASKSPOT_ID} PRIVATE
               ${TASKSPOT_ID}.cpp
               backend.cpp
               filtermodel.cpp
               smartlauncherbackend.cpp
               smartlauncheritem.cpp)

kconfig_add_kcfg_files(${TASKSPOT_ID} ${CMAKE_CURRENT_SOURCE_DIR}/kactivitymanagerd_plugins_settings.kcfgc)

ecm_qt_declare_logging_category(${TASKSPOT_ID}
    HEADER log_settings.h
    IDENTIFIER TASKSPOT_DEBUG
    CATEGORY_NAME com.stack-tech.plasma.taskspot)

# FIXME Cleanup no longer used libs.
target_link_libraries(${TASKSPOT_ID} PRIVATE
                      Qt::Core
                      Qt::Qml
                      Qt::Quick
                      Plasma::Activities
                      Plasma::ActivitiesStats
                      KF6::ConfigGui
                      KF6::CoreAddons # generated applet class (KPluginFactory)
                      KF6::I18n
                      KF6::KIOCore
                      KF6::KIOGui
                      KF6::KIOFileWidgets # KFilePlacesModel
                      KF6::Notifications # KNotificationJobUiDelegate
                      Plasma::Plasma # generated applet class
                      KSysGuard::ProcessCore
                      KF6::Service
                      KF6::WindowSystem
                      PW::LibNotificationManager)

install(TARGETS ${TASKSPOT_ID} DESTINATION ${KDE_INSTALL_PLUGINDIR}/plasma/applets)

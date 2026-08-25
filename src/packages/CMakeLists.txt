# SPDX-License-Identifier: GPL-2.0-or-later
# TaskSpot ships as a package-only sibling applet (X-Plasma-RootPath), not a
# second compiled plugin. Two compiled task-manager plugins in one plasmashell
# process collide on their identically-named C++ QML types and break the
# context menu of whichever applet loses the race. See issue #10.

install(DIRECTORY org.kde.taskspot
        DESTINATION ${KDE_INSTALL_DATADIR}/plasma/plasmoids)

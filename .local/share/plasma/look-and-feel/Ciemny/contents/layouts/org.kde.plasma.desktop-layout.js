var plasma = getApiVersion(1);

var layout = {
    "desktops": [
        {
            "applets": [
            ],
            "config": {
                "/": {
                    "ItemGeometries-1920x1080": "",
                    "ItemGeometriesHorizontal": "",
                    "formfactor": "0",
                    "immutability": "1",
                    "lastScreen": "0",
                    "wallpaperplugin": "org.kde.image"
                },
                "/ConfigDialog": {
                    "DialogHeight": "630",
                    "DialogWidth": "810"
                },
                "/General": {
                    "changedPositions": "{}",
                    "lastResolution": "1920x1080",
                    "positions": "{\"1920x1080\":[\"1\",\"17\"]}",
                    "sortMode": "-1"
                },
                "/Wallpaper/org.kde.image/General": {

                },
                "/Wallpaper/org.kde.potd/General": {
                    "Provider": "bing",
                    "UpdateOverMeteredConnection": "1"
                }
            },
            "wallpaperPlugin": "org.kde.image"
        }
    ],
    "panels": [
        {
            "alignment": "center",
            "applets": [
                {
                    "config": {
                    },
                    "plugin": "org.kde.plasma.appmenu"
                },
                {
                    "config": {
                    },
                    "plugin": "org.kde.plasma.panelspacer"
                },
                {
                    "config": {
                        "/": {
                            "popupHeight": "348",
                            "popupWidth": "308"
                        },
                        "/ConfigDialog": {
                            "DialogHeight": "630",
                            "DialogWidth": "810"
                        },
                        "/General": {
                            "customButtonImage": "yast-kernel",
                            "favoriteSystemActions": "",
                            "favoritesPortedToKAstats": "true",
                            "useCustomButtonImage": "true"
                        }
                    },
                    "plugin": "org.kde.plasma.kicker"
                },
                {
                    "config": {
                    },
                    "plugin": "org.kde.plasma.marginsseparator"
                },
                {
                    "config": {
                        "/": {
                            "popupHeight": "451",
                            "popupWidth": "810"
                        },
                        "/Appearance": {
                            "dateDisplayFormat": "BesideTime",
                            "dateFormat": "longDate",
                            "enabledCalendarPlugins": "astronomicalevents,holidaysevents",
                            "fontWeight": "400",
                            "showSeconds": "Always",
                            "showWeekNumbers": "true"
                        },
                        "/ConfigDialog": {
                            "DialogHeight": "630",
                            "DialogWidth": "810"
                        }
                    },
                    "plugin": "org.kde.plasma.digitalclock"
                },
                {
                    "config": {
                    },
                    "plugin": "org.kde.plasma.marginsseparator"
                },
                {
                    "config": {
                        "/": {
                            "popupHeight": "321",
                            "popupWidth": "519"
                        },
                        "/Appearance": {
                            "showPressureInTooltip": "true",
                            "showTemperatureInCompactMode": "true"
                        },
                        "/ConfigDialog": {
                            "DialogHeight": "630",
                            "DialogWidth": "810"
                        },
                        "/WeatherStation": {
                            "placeDisplayName": "Warsaw, Poland, PL",
                            "placeInfo": "Warsaw, Poland, PL|756135",
                            "provider": "bbcukmet"
                        }
                    },
                    "plugin": "org.kde.plasma.weather"
                },
                {
                    "config": {
                    },
                    "plugin": "org.kde.plasma.marginsseparator"
                },
                {
                    "config": {
                        "/ConfigDialog": {
                            "DialogHeight": "630",
                            "DialogWidth": "810"
                        },
                        "/General": {
                            "actionsOrder": "lockScreen,switchUser,requestShutDown,requestReboot,requestLogout,requestLogoutScreen,suspendToRam,suspendToDisk",
                            "show_lockScreen": "false",
                            "show_requestLogoutScreen": "false",
                            "show_requestReboot": "true",
                            "show_requestShutDown": "true"
                        }
                    },
                    "plugin": "org.kde.plasma.lock_logout"
                },
                {
                    "config": {
                    },
                    "plugin": "org.kde.plasma.panelspacer"
                },
                {
                    "config": {
                        "/": {
                            "popupHeight": "298",
                            "popupWidth": "289"
                        }
                    },
                    "plugin": "org.kde.plasma.calculator"
                },
                {
                    "config": {
                        "/": {
                            "popupHeight": "325",
                            "popupWidth": "373"
                        },
                        "/ConfigDialog": {
                            "DialogHeight": "630",
                            "DialogWidth": "810"
                        },
                        "/General": {
                            "color": "translucent",
                            "cursorPosition": "0",
                            "fontSize": "10",
                            "noteId": "453c4c4b-2a5c-44ac-8aa0-a5fbfeeb54"
                        }
                    },
                    "plugin": "org.kde.plasma.notes"
                },
                {
                    "config": {
                    },
                    "plugin": "org.kde.plasma.marginsseparator"
                },
                {
                    "config": {
                    },
                    "plugin": "org.kde.plasma.systemtray"
                },
                {
                    "config": {
                        "/ConfigDialog": {
                            "DialogHeight": "630",
                            "DialogWidth": "810"
                        },
                        "/General": {
                            "fontSize": "150"
                        }
                    },
                    "plugin": "org.kde.netspeedWidget"
                },
                {
                    "config": {
                    },
                    "plugin": "org.kde.plasma.showdesktop"
                }
            ],
            "config": {
                "/": {
                    "formfactor": "2",
                    "immutability": "1",
                    "lastScreen": "0",
                    "wallpaperplugin": "org.kde.image"
                }
            },
            "height": 2.6666666666666665,
            "hiding": "normal",
            "location": "top",
            "maximumLength": 106.66666666666667,
            "minimumLength": 106.66666666666667,
            "offset": 0
        },
        {
            "alignment": "center",
            "applets": [
                {
                    "config": {
                        "/General": {
                            "launchers": "preferred://
                        }
                    },
                    "plugin": "org.kde.plasma.icontasks"
                }
            ],
            "config": {
                "/": {
                    "formfactor": "2",
                    "immutability": "1",
                    "lastScreen": "0",
                    "wallpaperplugin": "org.kde.image"
                }
            },
            "height": 3.4444444444444446,
            "hiding": "dodgewindows",
            "location": "bottom",
            "maximumLength": 106.66666666666667,
            "minimumLength": 106.66666666666667,
            "offset": 0
        }
    ],
    "serializationFormatVersion": "1"
}
;

plasma.loadSerializedLayout(layout);

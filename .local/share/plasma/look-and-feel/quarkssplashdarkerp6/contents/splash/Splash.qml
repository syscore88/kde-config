import QtQuick
import QtQuick.Window

Rectangle {
    id: root
    color: "#0a0a0a"

    property int stage

    onStageChanged: {
        if (stage == 1) {
            introAnimation.running = true;
        } else if (stage == 5) {
            introAnimation.target = busyIndicator;
            introAnimation.from = 1;
            introAnimation.to = 0;
            introAnimation.running = true;
        }
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: 0

        TextMetrics {
            id: units
            text: "M"
            property int gridUnit: boundingRect.height
            property int largeSpacing: units.gridUnit
            property int smallSpacing: Math.max(2, gridUnit/4)
        }

        Rectangle {
            property int sizeAnim: 400

            id: imageSource
            width: sizeAnim
            height: sizeAnim
            color: "transparent"
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            clip: true

            AnimatedImage {
                id: face
                source: "images/plasma_d.gif"
                paused: false
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: imageSource.sizeAnim - 7
                height: imageSource.sizeAnim - 7
                smooth: true
                visible: true
            }
        }

        Image {
            id: busyIndicator
            y: parent.height - 150
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.margins: units.gridUnit
            source: "images/busywidget.svgz"
            sourceSize.height: units.gridUnit * 2
            sourceSize.width: units.gridUnit * 2
            RotationAnimator on rotation {
                from: 0
                to: 360
                duration: 1500
                loops: Animation.Infinite
            }
        }

        Row {
            spacing: units.smallSpacing * 2
            anchors {
                bottom: parent.bottom
                margins: units.gridUnit
            }
            anchors.horizontalCenter: parent.horizontalCenter

            Text {
                color: "#eff0f1"
                renderType: Screen.devicePixelRatio % 1 !== 0 ? Text.QtRendering : Text.NativeRendering
                anchors.verticalCenter: parent.verticalCenter
                text: ""
            }
            Image {
                source: "images/kde.svgz"
                sourceSize.height: units.gridUnit * 2
                sourceSize.width: units.gridUnit * 2
            }
        }
    }

    OpacityAnimator {
        id: introAnimation
        running: false
        target: content
        from: 0
        to: 1
        duration: 1000
        easing.type: Easing.InOutQuad
    }
}

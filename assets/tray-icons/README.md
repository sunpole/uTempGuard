# Generated tray icon cache

Этот каталог хранит автоматически подготовленные ASCII base64-файлы 64px PNG, построенные из оригинальных пользовательских SVG в assets/logo/. Оригинальные векторы не меняются.

GitHub Actions запускает tools/build-tray-icons.py после загрузки SVG и публикует файлы utg_w_*.png.base64 и utg_b_*.png.base64. Windows PowerShell 5.1 читает их локально без зависимости от CorelDRAW, Python или WebView2.

Если SVG пока не загружены, папка остаётся почти пустой, а программа показывает прежний официальный логотип. Подробнее: docs/TRAY_ICONS.md.

Скрипт для steamdeck для установки пакетов из AUR.
Что такое AUR?
AUR (сокращение от Arch User Repository) - репозиторий программ для arch linux который поддерживается пользователями.
На текущий момент один из самых больших репозиториев среди всех linux дистрибутивов.
В этом также и минус репозитория. Считается что в нем много мусора и, потенциально, скама.
Но пользователи самого aur теоретически следят сами за чистотой и явные проблемные пакеты помечают как непригодные. 
То есть в репозитории самомодерация.
Почему не установить пакет из flatpak, при помощи appimage или brew, nix, docker?
1. В flatpak далеко не все пакеты доступные для arch linux
2. appimage - аналогично
3. brew, nix, docker - слишком сложно для среднестатистического пользователя steamdeck.

Что делает скрипт?
Скрипт временно переключает steamos в режим записи на системный раздел,
временно выключает запросы на ввод пароля администратора,
инициализирует хранилище ключей pacman и обновляет их,
проверяет и устанавливает клиент для aur (под названием yay),
затем ищет пакет который необходимо установить и ставит его.
В конце скрипт возвращает запрос пароля и переключает систему обратно в режим только для чтения.

Как установить?
В терминале ввести wget -O - https://raw.githubusercontent.com/deathmond1987/steamdeck/refs/heads/main/install_from_aur.sh | bash

Как пользоваться?
Пример установки пакета:
./install_from_aur.sh install openenroth - установит пакет с названием openenroth
./install_from_aur.sh install openenroth dive - установить пакеты с названием openenroth и dive
Пример удаления пакета:
./install_from_aur.sh remove openenroth - удалит пакет с названием openenroth
./install_from_aur.sh remove openenroth dive - удалит пакеты с названием openenroth и dive
Интерактивный режим:
./install_from_aur.sh openenroth - запустит поиск по имени openenroth в репозитории aur.
затем выведет список всех пакетов по найденному имени с вопросом какой из пакетов ставить и предложит поставить его

# Обычный DNS существующих провайдеров

Адреса и инструкции операторов сверены 2026-10-12. Встроенный список использует опубликованные IPv4; пользовательские записи поддерживают IPv4 и IPv6. Проверяются все перечисленные IP отдельно по UDP/53 и TCP/53. Вариант фильтрации по возможности соответствует существующим DoH/DoT.

Пустое поле означает, что общедоступный адрес обычного DNS не подтверждён; это не результат сетевого теста и не утверждение о недоступности сервиса. IP шифрованного endpoint не переносится автоматически на порт 53. Проверка во время запуска определяет доступность с конкретного сервера.

| Провайдер | Обычные IPv4 | Вариант / причина пропуска | Источник |
| --- | --- | --- | --- |
| Yandex | 77.88.8.8, 77.88.8.1 | Базовый режим | [Источник](https://dns.yandex.ru/) |
| Cloudflare | 1.1.1.1, 1.0.0.1 | Без фильтрации | [Источник](https://developers.cloudflare.com/1.1.1.1/ip-addresses/) |
| Google | 8.8.8.8, 8.8.4.4 | Public DNS | [Источник](https://developers.google.com/speed/public-dns/docs/using) |
| Quad9 | 9.9.9.9, 149.112.112.112 | Рекомендуемый защищённый режим | [Источник](https://quad9.net/service/service-addresses-and-features/) |
| AdGuard | 94.140.14.14, 94.140.15.15 | Default | [Источник](https://adguard-dns.io/en/blog/adguard-dns-new-addresses.html) |
| Mullvad | — | Оператор прямо исключает UDP/53 и TCP/53 | [Источник](https://mullvad.net/en/help/dns-over-https-and-dns-over-tls) |
| CleanBrowsing | 185.228.168.9, 185.228.169.9 | Security Filter | [Источник](https://cleanbrowsing.org/filters/) |
| DNS.SB | 185.222.222.222, 45.11.45.11 | Публичные DNS | [Источник](https://dns.sb/guide/) |
| DNSPod | 119.29.29.29 | Публикация команды DNSPod; подтверждён один IPv4 | [Источник](https://developer.cloud.tencent.com/article/2278854) |
| AliDNS | 223.5.5.5, 223.6.6.6 | Публичные DNS | [Источник](https://www.alidns.com/) |
| 360DNS | 101.226.4.6, 218.30.118.6 | Пара для China Telecom / Unicom / Mobile | [Источник](https://sdns.360.net/) |
| ControlD | 76.76.2.0, 76.76.10.0 | Unfiltered / p0 | [Источник](https://docs.controld.com/docs/free-dns) |
| Wikimedia | — | Опубликованы DoH/DoT; обычный публичный DNS не подтверждён | [Источник](https://meta.wikimedia.org/wiki/Wikimedia_DNS) |
| DNS4EU | 86.54.11.100, 86.54.11.200 | Unfiltered | [Источник](https://joindns4.eu/for-public) |
| OpenDNS | 208.67.222.222, 208.67.220.220 | Публичные DNS | [Источник](https://www.opendns.com/) |
| LibreDNS | — | Опубликованы DoH/DoT; IP для DoT не считается подтверждением порта 53 | [Источник](https://libredns.gr/) |
| dnsforge | 49.12.67.122, 91.99.154.175, 176.9.93.198, 176.9.1.117 | Normal | [Источник](https://dnsforge.de/) |
| DNSwarden | — | Опубликованы зашифрованные протоколы; порт 53 не подтверждён | [Источник](https://dnswarden.com/) |
| DigitaleGesell. | — | Оператор прямо не предоставляет порт 53 | [Источник](https://www.digitale-gesellschaft.ch/dns/) |
| FFMUC | 5.1.66.255, 185.150.99.255 | Plain DNS / anycast | [Источник](https://dns-setup.ffmuc.net/) |
| UncensoredDNS | — | Текущая страница публикует порты 853 и 443; порт 53 не подтверждён | [Источник](https://blog.uncensoreddns.org/dns-servers/) |
| FDN | 80.67.169.12, 80.67.169.40 | Открытые рекурсивные DNS | [Источник](https://www.fdn.fr/actions/dns/) |
| RethinkDNS | — | Опубликованы зашифрованные адреса; порт 53 не подтверждён | [Источник](https://rethinkdns.com/configure) |
| AppliedPrivacy | — | Оператор прямо не поддерживает обычный UDP/53 | [Источник](https://applied-privacy.net/services/dns/) |
| CIRA | 149.112.121.10, 149.112.122.10 | Private | [Источник](https://www.cira.ca/en/how-canadian-shield-works/) |
| Comss.one | 83.220.169.155, 212.109.195.93 | Стандартные серверы; отдельные IP от шифрованного сервиса | [Источник](https://www.comss.ru/page.php?id=7315) |
| CZ.NIC | 193.17.47.1, 185.43.135.1 | ODVR | [Источник](https://www.nic.cz/odvr/) |
| IIJ | — | Опубликованы DoH/DoT; обычный публичный DNS не подтверждён | [Источник](https://policy.public.dns.iij.jp/) |
| Restena | — | Опубликованы DoH/DoT; обычный публичный DNS не подтверждён | [Источник](https://restena.lu/en/document/190-configuring-your-server-public-dns-resolver) |
| SWITCH | — | Публичный сервис описан с транспортным шифрованием | [Источник](https://portal.switch.ch/pub/public-dns/) |
| Njalla | 95.215.19.53 | Public DNS | [Источник](https://dns.njal.la/) |
| BlahDNS-DE | — | Опубликованы зашифрованные протоколы; порт 53 не подтверждён | [Источник](https://blahdns.com/) |
| dismail | 116.203.32.217, 159.69.114.157 | Оба DNS Resolver: fdns1 / fdns2 | [Источник](https://dismail.de/info.html) |
| OpenBLD | — | Обычный публичный DNS не подтверждён | [Источник](https://openbld.net/) |
| BebasDNS | — | Plain DNS ограничен разрешёнными диапазонами; публичные IP не опубликованы в текущей таблице | [Источник](https://github.com/bebasid/bebasdns) |
| DigitalSize | — | Опубликованы DoH/DoT; обычный публичный DNS не подтверждён | [Источник](https://dns.digitalsize.net/) |
| HaGeZi | — | Адреса опубликованы для шифрованных протоколов; порт 53 не подтверждён | [Источник](https://github.com/hagezi/dns-servers/blob/main/CHEATSHEET.md) |
| dnscry.pt-Lisbon | — | Опубликованы зашифрованные протоколы; порт 53 не подтверждён | [Источник](https://www.dnscry.pt/public-resolvers/lis01) |
| DNS4all | 194.0.5.3 | Стандартный Do53, без DNS64 | [Источник](https://dns4all.eu/) |
| Belnet | — | Обычные резолверы предназначены организациям сети Belnet; публичен DoH | [Источник](https://www.belnet.be/en/communities-services/all-services/connectivity-and-internet/dns-service/dns-service-technical-faq) |
| CERT-EE | — | Текущая инструкция для шифрованного DNS; публичные IP обычного DNS не подтверждены | [Источник](https://ria.ee/kuberturvalisus/kuberintsidentide-kasitlemine-cert-ee/cert-ee-tooriistad-ja-teenused) |

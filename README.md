# Проверки сервера и сети

Один запуск выполняет девять проверок по очереди: IP region, Censorcheck (геоблок и DPI), тест до российских iPerf3 серверов, YABS, IP.Check.Place, bench.sh, IPQuality и однопоточный тест CPU в sysbench.

## Запуск

На Linux сервере нужны Bash, curl и доступ в интернет. Для последней проверки установите `sysbench`; без него она будет помечена `SKIPPED`. Остальные утилиты, нужные отдельным проверкам, могут устанавливаться или запрашиваться самими исходными скриптами.

```bash
git clone https://github.com/KirillShchetinnikov/server-network-bench.git
cd server-network-bench
bash run.sh
```

Выбор отдельных проверок:

```bash
bash run.sh --list
bash run.sh --only ip-region --only censorcheck-geoblock
```

Вывод каждой проверки сохраняется в `reports/<UTC-время>/<имя>.log` относительно текущего каталога, итог — в `summary.tsv`. Путь можно переопределить переменной `REPORT_DIR`. Другие проверки продолжаются, если одна завершилась ошибкой. При любой ошибке загрузки или выполнения общий код выхода равен 1. `SKIPPED` означает отсутствие `sysbench` и не считается ошибкой.

Запуск напрямую через GitHub Pages на своём домене:

```bash
bash <(curl -fsSL https://bench.kipik1.ru/run.sh)
```

Страница с описанием доступна по адресу <https://bench.kipik1.ru/>.

По умолчанию YABS запускается с `-4`: это выбор **Geekbench 4**, как в исходной команде. Если нужна проверка IPv4 на более новой версии Geekbench, параметр следует изменить.

Скрипт загружает и выполняет актуальные версии сторонних программ во время запуска. Некоторые проверки активно нагружают CPU, диск и сеть, могут расходовать трафик и создавать временные файлы. Запускайте их на сервере, который вы контролируете, после просмотра исходников по ссылкам ниже.

## Источники

- [IP region](https://ipregion.vrnt.xyz)
- [Censorcheck](https://github.com/vernette/censorcheck)
- [Российские iPerf3 серверы](https://github.com/itdoginfo/russian-iperf3-servers)
- [YABS](https://github.com/masonr/yet-another-bench-script)
- [IP.Check.Place](https://ip.check.place)
- [bench.sh](https://bench.sh)
- [IPQuality / Check.Place](https://check.place)
- [sysbench](https://github.com/akopytov/sysbench)

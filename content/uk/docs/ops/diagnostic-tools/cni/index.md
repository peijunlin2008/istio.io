---
title: Усунення неполадок втулка Istio CNI
description: Описує інструменти та техніки для діагностики проблем за допомогою Istio з втулком CNI.
weight: 95
keywords: [debug,cni]
owner: istio/wg-networking-maintainers
test: n/a
---

Ця сторінка описує, як усунути неполадки з втулком Istio CNI. Перед читанням цього, ви повинні прочитати [Посібник з встановлення та роботи з CNI](/docs/setup/additional-setup/cni/).

## Логи {#log}

Лог втулка Istio CNI надає інформацію про те, як втулок конфігурує перенаправлення трафіку застосунків на основі `PodSpec`.

Втулок працює у просторі процесу контейнерного середовища, тому ви можете побачити записи логів CNI в журналі `kubelet`. Щоб спростити налагодження, втулок CNI також надсилає свій лог до DaemonSet `istio-cni-node`.

Рівень логів для втулка CNI стандартно — `info`. Щоб отримати більш детальний вивід логів, ви можете змінити рівень, відредагувавши опцію встановлення `values.cni.logLevel` і перезапустивши pod DaemonSet CNI.

Лог pod DaemonSet Istio CNI також надає інформацію про встановлення втулка CNI, та [виправлення стану перегонів](/docs/setup/additional-setup/cni/#race-condition--mitigation).

## Моніторинг {#monitoring}

DaemonSet CNI [генерує метрики](/docs/reference/commands/install-cni/#metrics), які можна використовувати для моніторингу встановлення CNI, готовності та виправлення стану перегонів. Анотації для збору метрик Prometheus (`prometheus.io/port`, `prometheus.io/path`) стандартно додаються до pod DaemonSet `istio-cni-node`. Ви можете збирати згенеровані метрики за допомогою стандартної конфігурації Prometheus.

## Готовність DaemonSet {#daemonset-readiness}

Готовність DaemonSet CNI вказує на те, що втулок Istio CNI правильно встановлений і сконфігурований. Якщо DaemonSet Istio CNI не готовий, це свідчить про те, що щось не так. Перегляньте логи DaemonSet `istio-cni-node`, щоб діагностувати. Ви також можете відстежувати готовність встановлення CNI через метрику `istio_cni_install_ready`.

## Виправлення стану перегонів {#race-condition-repair}

Стандартно, DaemonSet Istio CNI має [виправлення стану перегонів](/docs/setup/additional-setup/cni/#race-condition--mitigation), яке видаляє pod, що був запущений до того, як втулок CNI був готовий. Щоб зрозуміти, які podʼи були видалені, шукайте рядки в логах, подібні до наступних:

{{< text plain >}}
2021-07-21T08:32:17.362512Z     info   Deleting broken pod: service-graph00/svc00-0v1-95b5885bf-zhbzm
{{< /text >}}

Ви також можете відстежувати podʼи, що були виправлені, через метрику `istio_cni_repair_pods_repaired_total`.

## Діагностика помилки запуску podʼа {#diagnose-pod-start-up-failure}

Звичайною проблемою з втулком CNI є те, що pod не запускається через невдачу налаштування мережі контейнера. Зазвичай причина невдачі записується у події podʼа і видима через опис podʼа:

{{< text bash >}}
$ kubectl describe pod POD_NAME -n POD_NAMESPACE
{{< /text >}}

Якщо pod постійно отримує помилку ініціалізації, перевірте лог контейнера ініціалізації `istio-validation` на помилки типу "connection refused" подібні до наступних:

{{< text bash >}}
$ kubectl logs POD_NAME -n POD_NAMESPACE -c istio-validation
...
2021-07-20T05:30:17.111930Z     error   Error connecting to 127.0.0.6:15002: dial tcp 127.0.0.1:0->127.0.0.6:15002: connect: connection refused
2021-07-20T05:30:18.112503Z     error   Error connecting to 127.0.0.6:15002: dial tcp 127.0.0.1:0->127.0.0.6:15002: connect: connection refused
...
2021-07-20T05:30:22.111676Z     error   validation timeout
{{< /text >}}

Контейнер ініціалізації `istio-validation` налаштовує локальний фальшивий сервер, який слухає порти перенаправлення трафіку на вході/виході, і перевіряє, чи тестовий трафік може бути перенаправлений на фальшивий сервер. Коли перенаправлення трафіку podʼа не налаштоване правильно втулком CNI, контейнер ініціалізації `istio-validation` блокує запуск podʼа, щоб запобігти обходу трафіку. Щоб перевірити, чи були помилки або несподівані поведінки налаштування мережі, пошукайте в `istio-cni-node` за ідентифікатором podʼа.

Ще одним симптомом неправильно працюючого втулка CNI є те, що pod застосунку постійно видаляється під час запуску. Це зазвичай відбувається через те, що втулок неправильно встановлений, і тому перенаправлення трафіку podʼа не може бути налаштоване. Логіка [виправлення стану перегонів CNI](/docs/setup/additional-setup/cni/#race-condition--mitigation) вважає pod пошкодженим через стан перегонів та постійно видаляє pod. При виникненні цієї проблеми перевірте лог DaemonSet CNI для інформації про те, чому втулок не був правильно встановлений.

---
title: Розуміння маршрутизації трафіку
linktitle: Маршрутизація трафіку
description: Як Istio маршрутизує трафік через mesh.
weight: 32
keywords: [traffic-management,proxy]
owner: istio/wg-networking-maintainers
test: n/a
---

Однією з цілей Istio є діяти як "прозорий проксі", який може бути інтегрований у вже наявний кластер, дозволяючи трафіку продовжувати протікати, як раніше. Однак Istio надає потужні можливості для управління трафіком, які відрізняються від типового кластера Kubernetes завдяки додатковим функціям, як, наприклад, балансування навантаження на запити. Щоб зрозуміти, що відбувається у вашому mesh, важливо розібратися, як Istio маршрутизує трафік.

{{< warning >}}
Цей документ описує деталі низькорівневої реалізації. Для загального огляду ознайомтесь з [концепціями](/docs/concepts/traffic-management/) управління трафіком або [завданнями](/docs/tasks/traffic-management/).
{{< /warning >}}

## Фронтенди та бекенди {#frontends-and-backends}

У маршрутизації трафіку в Istio існують два основні етапи:

* "Фронтенд" визначає, як ми зіставляємо тип трафіку, який обробляємо. Це необхідно для того, щоб визначити, до якого бекенду спрямовувати трафік і які політики застосовувати. Наприклад, ми можемо прочитати заголовок `Host` з адресою `http.ns.svc.cluster.local` і визначити, що запит призначений для сервісу `http`. Більше інформації про цей процес можна знайти нижче.
* "Бекенд" визначає, куди ми направляємо трафік після того, як зіставили його. Використовуючи попередній приклад, після ідентифікації запиту, як такого, що спрямований до сервісу `http`, ми надсилаємо його на одну з точок доступу цього сервісу. Однак вибір не завжди є таким простим; Istio дозволяє налаштовувати цей процес через правила маршрутизації `VirtualService`.

Стандартне управління мережею в Kubernetes також має ці поняття, але вони значно простіші і, зазвичай, приховані. Коли створюється сервіс `Service`, зазвичай створюється відповідний фронтенд — автоматично створюється DNS-імʼя (наприклад, `http.ns.svc.cluster.local`) і автоматично створюється IP-адреса для представлення сервісу (`ClusterIP`). Аналогічно створюється бекенд — `Endpoints` або `EndpointSlice`, які представляють всі підібрані для сервісу pod'и.

## Протоколи {#protocols}

На відміну від Kubernetes, Istio може обробляти протоколи на рівні застосунків, такі як HTTP і TLS. Це дозволяє використовувати інший тип зіставлення для [фронтендів](#frontends-and-backends), ніж у Kubernetes.

Загалом, Istio розуміє три основні класи протоколів:

* HTTP, який включає HTTP/1.1, HTTP/2 і gRPC. Зверніть увагу, що це не включає зашифрований трафік TLS (HTTPS).
* TLS, який включає HTTPS.
* Необроблені TCP-байти.

Документ про [вибір протоколів](/docs/ops/configuration/traffic-management/protocol-selection/) описує, як Istio визначає, який протокол використовується.

Використання "TCP" може бути заплутаним, оскільки в інших контекстах цей термін використовується для розрізнення між іншими L4-протоколами, такими як UDP. У контексті Istio, TCP зазвичай означає, що ми працюємо з необробленим потоком байтів, а не з протоколами на рівні застосунків, такими як TLS або HTTP.

## Маршрутизація трафіку {#traffic-routing}

Коли проксі Envoy отримує запит, він повинен вирішити, куди, якщо взагалі, його пересилати. Стандартно, запит буде пересланий до початкового сервісу, який було запитано, якщо не було [налаштовано інше](/docs/tasks/traffic-management/traffic-shifting/). Те, як це працює, залежить від використовуваного протоколу.

### TCP {#tcp}

При обробці TCP-трафіку Istio має дуже мало корисної інформації для маршрутизації зʼєднання — лише IP-адресу призначення і порт. Ці атрибути використовуються для визначення призначеного сервісу; проксі налаштований на прослуховування кожної пари IP-адреса сервісу (`<Kubernetes ClusterIP>:<Port>`) і пересилання трафіку до висхідного сервісу.

Для налаштувань можна створити TCP `VirtualService`, який дозволяє [зіставляти певні IP-адреси та порти](/docs/reference/config/networking/virtual-service/#L4MatchAttributes) та маршрутизувати їх до інших висхідних сервісів.

### TLS {#tls}

При обробці TLS-трафіку Istio має трохи більше інформації, ніж при роботі з необробленим TCP: можна проаналізувати поле [SNI](https://en.wikipedia.org/wiki/Server_Name_Indication), представлене під час TLS-handshake.

Для стандартних сервісів використовується те ж саме зіставлення IP:Port, що і для необробленого TCP. Однак для сервісів, які не мають визначеної IP-адреси, таких як [ExternalName-сервіси](#externalname-services), для маршрутизації використовується поле SNI.

Крім того, можна налаштувати маршрутизацію за допомогою TLS `VirtualService`, щоб [зіставляти SNI](/docs/reference/config/networking/virtual-service/#TLSMatchAttributes) та перенаправляти запити до власних призначень.

### HTTP {#http}

HTTP дозволяє набагато більш багаті можливості маршрутизації, ніж TCP та TLS. За допомогою HTTP можна маршрутизувати окремі HTTP-запити, а не лише зʼєднання. Крім того, доступні [численні розширені атрибути](/docs/reference/config/networking/virtual-service/#HTTPMatchRequest), такі як хост, шлях, заголовки, параметри запиту тощо.

Трафік TCP і TLS зазвичай поводиться однаково з або без Istio (якщо не було налаштовано власну маршрутизацію), тоді як для HTTP є суттєві відмінності.

* Istio буде балансувати навантаження на рівні окремих запитів. Загалом, це є дуже бажаним, особливо у сценаріях з довготривалими зʼєднаннями, такими як gRPC і HTTP/2, де балансування на рівні зʼєднань є неефективним.
* Запити маршрутизуються на основі порту та *заголовку `Host`*, а не порту та IP. Це означає, що IP-адреса призначення фактично ігнорується. Наприклад, `curl 8.8.8.8 -H "Host: productpage.default.svc.cluster.local"` буде перенаправлено до сервісу `productpage`.

## Незіставлений трафік {#unmatched-traffic}

Якщо трафік не може бути зіставлений за одним з описаних методів, він обробляється як [passthrough трафік](/docs/tasks/traffic-management/egress/egress-control/#envoy-passthrough-to-external-services). Стандартно, такі запити будуть пересилатися без змін, що гарантує функціонування трафіку до сервісів, про які Istio не має інформації (наприклад, зовнішні сервіси без створених `ServiceEntry`). Зверніть увагу, що під час пересилання таких запитів mutual TLS не буде використовуватися, а збір телеметрії буде обмеженим.

## Типи сервісів {#service-types}

Разом зі стандартними сервісами `ClusterIP`, Istio підтримує повний спектр сервісів Kubernetes, з певними застереженнями.

### Сервіси `LoadBalancer` та `NodePort` {#loadbalancer-and-nodeport-services}

Ці сервіси є надмножинами сервісів `ClusterIP` і здебільшого стосуються забезпечення доступу ззовні. Ці типи сервісів підтримуються і функціонують так само як стандартні сервіси `ClusterIP`.

### Headless сервіси {#headless-services}

[Headless сервіс](https://kubernetes.io/docs/concepts/services-networking/service/#headless-services) — це сервіс, який не має призначеного `ClusterIP`. Натомість відповідь DNS міститиме IP-адреси кожної точки доступу (тобто IP-адреси Pod), що є частиною сервісу.

Загалом, Istio не налаштовує слухачів для кожної IP-адреси Pod, оскільки працює на рівні сервісу. Проте для підтримки headless сервісів слухачі налаштовуються для кожної пари IP:Port у headless сервісі. Винятком є протоколи, оголошені як HTTP, які відповідатимуть трафіку за заголовком `Host`.

{{< warning >}}
Без Istio поле `ports` у headless сервісі не є суворо обовʼязковим, оскільки запити йдуть безпосередньо до IP-адрес Pod, які можуть приймати трафік на всіх портах. Однак з Istio порт повинен бути оголошений у сервісі, інакше трафік [не буде зіставлятись](/docs/ops/configuration/traffic-management/traffic-routing/#unmatched-traffic).
{{< /warning >}}

### Сервіси ExternalName {#externalname-services}

[Сервіс ExternalName](https://kubernetes.io/docs/concepts/services-networking/service/#externalname) — це, по суті, DNS-аліас.

Щоб зробити все більш конкретним, розгляньмо такий приклад:

{{< text yaml >}}
apiVersion: v1
kind: Service
metadata:
  name: alias
spec:
  type: ExternalName
  externalName: concrete.example.com
{{< /text >}}

Оскільки немає ні `ClusterIP`, ні IP-адрес Pod, за якими можна було б здійснювати зіставлення, для TCP-трафіку змін у відповідності трафіку в Istio взагалі немає. Коли Istio отримує запит, він бачить IP для `concrete.example.com`. Якщо це сервіс, про який Istio знає, трафік буде спрямований, як описано [вище](#tcp). Якщо ні, він буде оброблений як [незіставлений трафік](#unmatched-traffic).

Для HTTP і TLS, де зіставлення здійснюється за імʼям хосту, ситуація дещо інша. Якщо цільовий сервіс (`concrete.example.com`) є сервісом, про який знає Istio, то імʼя хосту-аліаса (`alias.default.svc.cluster.local`) буде додано як *додатковий* варіант відповідності для [TLS](#tls) або [HTTP](#http). Якщо ні, змін не буде, і трафік буде оброблено як [незіставлений трафік](#unmatched-traffic).

Сервіс `ExternalName` ніколи не може бути [бекендом](#frontends-and-backends) сам по собі. Він використовується лише як додатковий варіант зіставлення [фронтенду](#frontends-and-backends) для наявних сервісів. Якщо його явно використовувати як бекенд, наприклад, у пункті призначення `VirtualService`, діятиме таке ж використання аліасів. Тобто якщо вказано `alias.default.svc.cluster.local` як пункт призначення, запити будуть надходити на `concrete.example.com`. Якщо це імʼя хосту не відоме Istio, запити завершаться невдачею; у цьому випадку конфігурацію може виправити додавання `ServiceEntry` для `concrete.example.com`.

### ServiceEntry {#serviceentry}

Окрім сервісів Kubernetes, можна створювати [Service Entries](/docs/reference/config/networking/service-entry/#ServiceEntry), щоб розширити набір сервісів, відомих Istio. Це може бути корисним для того, щоб забезпечити, наприклад, що трафік до зовнішніх сервісів, таких як `example.com`, отримував функціональність Istio.

ServiceEntry з встановленим полем `addresses` виконуватиме маршрутизацію так само як сервіс `ClusterIP`.

Однак для Service Entry без жодних `addresses` всі IP на порту будуть мати збіг. Це може перешкодити правильній передачі [незіставленого трафіку](#unmatched-traffic) на тому ж порту. Отже, бажано уникати таких конфігурацій, коли можливо, або використовувати виділені порти в разі потреби. Це обмеження не стосується HTTP і TLS, оскільки маршрутизація для них здійснюється на основі імені хосту/SNI.

{{< tip >}}
Поле `addresses` і поле `endpoints` часто плутають. `addresses` стосується IP-адрес, з якими буде здійснюватися зіставлення, тоді як точки доступу — це набір IP-адрес, на які буде направлений трафік.

Наприклад, наведений нижче запис Service Entry буде відповідати трафіку для `1.1.1.1` і направляти запит до `2.2.2.2` і `3.3.3.3` відповідно до налаштованої політики балансування навантаження:

{{< text yaml >}}
addresses: [1.1.1.1]
resolution: STATIC
endpoints:
- address: 2.2.2.2
- address: 3.3.3.3
{{< /text >}}

{{< /tip >}}

# 🛡️ Bloc Error Control

**Продвинутое решение для обработки ошибок и управления жизненным циклом событий в Flutter-приложениях
на базе BLoC. Пакет превращает хаотичные асинхронные исключения в структурированные состояния,
предотвращая утечки памяти и ресурсов.**

## 🎯 Когда использовать этот пакет

✅ **Используйте, если:**
- У вас крупный проект (50+ событий)
- Вы устали от try-catch boilerplate
- Вам нужна автоматическая отмена запросов
- Вы готовы изучить Zones

❌ **НЕ используйте, если:**
- У вас маленький проект (до 10 событий)
- Вы не знакомы с Zones
- Вам проще написать try-catch

---

## 🎯 Зачем это нужно?

### Проблема: типичный BLoC-код

```dart
on<LoadUser>((event, emit) async {
  emit(UserLoading());
  try {
    final user = await userRepository.getUser(event.id);
    emit(UserLoaded(user));
  } on SocketException {
    emit(UserError('Нет интернета'));
  } on ApiException catch (e) {
    emit(UserError(e.message));
  } catch (e, stack) {
    logger.error('Unexpected', error: e, stackTrace: stack);
    emit(UserError('Что-то пошло не так'));
  }
});
```

**Проблемы:**

- 80% кода — обработка ошибок
- Легко забыть обработать исключение
- Нет автоматической отмены "висячих" запросов

Решение: ваш код становится чистым

```dart
on<LoadUser>((event, emit) async {
  emit(UserLoading());
  final user = await userRepository.getUser(event.id, token: contextToken);
  emit(UserLoaded(user));
});
```

**Всё!** Ни одного try-catch. **Ошибки обрабатываются централизованно**.

## 📦 Возможности

| Фича                                     | Описание                                                           |
|:-----------------------------------------|:-------------------------------------------------------------------|
| **🚫 Нет try-catch**                     | Обработчики событий содержат только бизнес-логику                  |
| **🎯 Централизованная обработка ошибок** | `mapErrorToState` — один метод для всех ошибок                     |
| **🔌 Авто-отмена запросов**              | `contextToken` автоматически отменяет запросы при повторных событиях |
| **🧹 Cleanup при `close()`**             | Все активные запросы отменяются при закрытии блока                 |
| **📝 Гибкое логирование**                | Можно подключить любой логгер (Sentry, Firebase, свой)             |
| **⚡️ Работает с любыми трансформерами**  | `sequential()`, `restartable()`, `debounce()` и т.д.               |
| **🧬 Опциональная кодогенерация**        | Минимум бойлерплейта через аннотации                               |

## 🚀 Быстрый старт

```dart
class UserBloc extends Bloc<UserEvent, UserState>
    with BlocErrorControlMixin<UserEvent, UserState> {

  UserBloc() : super(UserInitial()) {
    on<LoadUserEvent>(_onLoadUser);
  }

  @override
  UserState? mapErrorToState(Object error, StackTrace stack, UserEvent event) {
    // Сюда попадают все ошибки из обработчиков
    if (error is SocketException) {
      return UserError('Нет интернета');
    }
    return UserError('Что-то пошло не так');
  }

  Future<void> _onLoadUser(LoadUserEvent event, Emitter<UserState> emit) async {
    emit(UserLoading());
    final user = await userRepository.getUser(event.id);
    emit(UserLoaded(user));
  }
}
```

## ⚡️ Сигналы (Side Effects)
**Сигналы** — это механизм для передачи одноразовых событий из `BLoC` в `UI` (показ `Snackbar`, `Toast`, 
навигация или запуск анимации).

### Какую проблему это решает?
В стандартном BLoC для показа уведомления об ошибке разработчики часто добавляют поле error в состояние (State). 

**Это приводит к ряду проблем**:
 - **Sticky State** (Липкая ошибка): При перестроении экрана (например, при повороте) Snackbar 
показывается снова, так как ошибка всё еще находится в состоянии.
 - **Загрязнение состояния**: Состояние должно описывать что на экране, а не что произошло один раз.

**Сигналы работают в параллельном потоке**: они не сохраняются в состоянии, доставляются один раз 
   и автоматически привязываются к контексту события.

### Использование в BLoC
Чтобы отправить сигнал, используйте метод `emitSignal()`. 

Вы также можете настроить автоматическое превращение ошибок в сигналы через `mapErrorToSignal`.

```dart
class UserBloc extends Bloc<UserEvent, UserState> with BlocErrorControlMixin<UserEvent, UserState> {
  UserBloc() : super(UserInitial()) {
    on<UpdateProfileEvent>((event, emit) async {
      await repo.updateUser(event.user);
      // Отправляем сигнал об успехе вручную
      emitSignal('Профиль успешно обновлен!');
    });
  }
  
  @override
  Object? mapErrorToSignal(Object error, StackTrace stack, UserEvent? event) {
    // Если произошла ошибка при лайке поста — не меняем стейт,
    // а просто уведомляем пользователя через сигнал
    if (event is LikePostEvent) {
      return 'Не удалось поставить лайк. Попробуйте позже.';
    }
    return null;
  }
}
```

### Обработка в UI (BlocSignalListener)
Для прослушивания сигналов используйте специальный виджет `BlocSignalListener`. 
Благодаря поддержке типов, вы можете слушать сигналы как от всего блока, так и от конкретных событий.

```dart
// Слушаем сигналы только от события UpdateProfileEvent
BlocSignalListener<UserBloc, UpdateProfileEvent>(
  onSignal: (context, signal) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(signal.toString())),
    );
  },
  child: ProfileScreen(),
)
```

### Преимущества сигналов в этой библиотеке
 - **Context-Aware**: Благодаря Zone API, каждый сигнал "знает", внутри какого события он был 
 отправлен. Это позволяет фильтровать уведомления в UI.
 - **Авто-отмена**: Если событие было отменено (например, через restartable), все сигналы, которые не 
   успели отправиться из его асинхронного кода, будут проигнорированы.
 - **Типобезопасность**: Вы можете передавать в качестве сигнала любые объекты (строки, sealed-классы, 
   DTO).

## Поддерживайте отмену запросов (опционально)

```dart
Future<void> _onSearch(SearchEvent event, Emitter<SearchState> emit) async {
  emit(SearchLoading());
  final results = await searchRepository.search(
    event.query,
    token: contextToken, // ← автоматическая отмена
  );
  emit(SearchLoaded(results));
}
```

## 🧬 Кодогенерация (опционально)

Если не хотите писать `if (event is LoadUserEvent`) в `mapErrorToState`,
либо переопределять метод `getErrorMapperForEvent`:

- Добавьте аннотацию на класс

```dart
import 'package:bloc_error_control/annotations.dart';

@BlocErrorControl() // ← добавить
class UserBloc extends Bloc<UserEvent, UserState>
    with BlocErrorControlMixin<UserEvent, UserState> {
  // ...
}
```

- Добавьте методы-мапперы с аннотацией

```dart
@ErrorStateFor<LoadUserEvent>()
UserState? onLoadUserError(Object error, StackTrace stack, LoadUserEvent event) {
  return UserError('Ошибка загрузки пользователя ${event.id}');
}

@ErrorStateFor<UpdateUserEvent>()
UserState? onUpdateUserError(Object error, StackTrace stack, UpdateUserEvent event) {
  return UserError('Ошибка обновления');
}
```

- Запустите генерацию

```bash
dart run build_runner build --delete-conflicting-outputs
```

## 📊 Производительность

| Метрика                | Результат        | Описание                                              |
|:-----------------------|:-----------------|:------------------------------------------------------|
| **Latency**            | **~49.4 µs**     | Задержка от `add(event)` до появления стейта          |
| **Throughput**         | **~69,000 ev/s** | Максимальная пропускная способность событий в секунду |
| **Memory Footprint**   | **0.02 MB**      | Добавочный вес 20,000 активных зон/токенов в RAM      |
| **`throwIfCancelled`** | **~0.006 µs**    | Стоимость одной проверки токена внутри цикла          |


## 🎯 Как это работает (коротко)

1. **Каждое событие** запускается в своей **зоне (Zone)**
2. В зоне создаётся **уникальный ICancelToken**
3. Если происходит ошибка, миксин:
- Ищет подходящий маппер (локальный → конкретный для события → глобальный)
- Превращает ошибку в состояние
- Логирует ошибку
4. При повторном событии — **предыдущий запрос отменяется**
5. При закрытии блока — **отменяются все активные запросы**

## 🧪 Тестовое покрытие
Пакет имеет **полное покрытие кода** тестами, включая все краевые случаи и 
асинхронные сценарии.

| Компонент | Покрытие |
|-----------|----------|
| **mixins/** | 100% |
| **models/** | 100% |
| **annotations/** | 100% |
| **exceptions/** | 100% |
| **Общее** | **100%** |

### Запуск тестов

```bash
flutter test test/bloc_error_control_mixin/unit/bloc_error_control_test.dart  
```

**Покрытие ветвлений (branch coverage)**
- Основная логика миксина имеет 84.6% branch coverage

**Генерация отчёта о покрытии:**
```bash
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html 
```

## 🔧 API Reference

| Метод                                                             | Описание                     |
|:------------------------------------------------------------------|:-----------------------------|
| **`S? mapErrorToState(Object error, StackTrace stack, E event)`** | Глобальный обработчик ошибок |

## Опциональные методы

| Метод                                                     | Описание                                |
|:----------------------------------------------------------|:----------------------------------------|
| **`set logger(ErrorLogger logger)`**                      | Подключить свой логгер                  |
| **`bool isGlobalSilent(Object error, StackTrace stack)`** | Фильтр "тихих" ошибок                   |
| **`ICancelToken get contextToken`**                       | Токен отмены для запросов               |
| **`void cancelTokensByEventType<T>()`**                   | Отменить все запросы определённого типа |
| **`List<Map<String, dynamic>> getActiveTokensInfo()`**    | Диагностика активных запросов           |

## Параметры on()

| Параметр          | Описание                                                     |
|:------------------|:-------------------------------------------------------------|
| **`transformer`** | Трансформер событий (`sequential()`, `restartable()` и т.д.) |
| **`timeout`**     | Таймаут события (по умолчанию 30 сек)                        |

## ⚠️ Требования

- Flutter >= 3.0.0
- flutter_bloc >= 8.0.0
- Dart >= 3.0.0

---

## ✨ Ключевые возможности

* **🛡️ Изоляция ошибок (Zone-based):** Перехватывает "дикие" асинхронные ошибки (в таймерах,
  микрозадачах), которые обычно роняют приложение.
* **🔌 Универсальный Токен (`contextToken`):** Автоматическое управление отменой (CancelToken) для
  сетевых запросов и тяжелых вычислений.
* **🚀 Нулевой оверхед:** Обработка одного события занимает менее **1 микросекунды**.
* **🧹 Чистота состояний:** Защита от "Zombie Emits" (попыток сменить стейт после закрытия события
  или Блока).
* **🤖 Кодогенерация (опционально):** Автоматическое создание мапперов ошибок через аннотации.
* **🔕 Тихие ошибки:** Встроенная фильтрация отмен (например, Dio cancel), которые не должны менять
  UI.

---

## ⚙️ Установка

Добавьте зависимости в ваш `pubspec.yaml`:

```yaml
dependencies:
  bloc_error_control: ^1.2.0

dev_dependencies:
  bloc_error_control_generator: ^1.1.2
  build_runner: ^2.10.0
```

## 🔌 Пример интеграции с Dio для ICancelToken

Для удобной работы с Dio HTTP клиентом пакет предоставляет расширение `DioCancelTokenX`, которое конвертирует `ICancelToken` в Dio `CancelToken`.

### Установка расширения

**Полный код расширения:**
```dart
extension DioCancelTokenX on ICancelToken {
  /// Converts [ICancelToken] to Dio's [CancelToken].
  CancelToken toDio() {
    final dioToken = CancelToken();

    if (isCancelled) {
      _safeCancel(dioToken);
      return dioToken;
    }

    unawaited(
      whenCancel.then((_) {
        _safeCancel(dioToken);
      }).catchError((_) {
        // Ошибка игнорируется
      }),
    );

    return dioToken;
  }

  void _safeCancel(CancelToken dioToken) {
    if (!dioToken.isCancelled) {
      final reason = this is EventCancelToken ? (this as EventCancelToken).reason : null;
      dioToken.cancel(reason);
    }
  }
}
```

- Использование
```dart
class UserBloc extends Bloc<UserEvent, UserState>
    with BlocErrorControlMixin<UserEvent, UserState> {
  
  final Dio _dio = Dio();

  Future<void> _onLoadUser(LoadUserEvent event, Emitter<UserState> emit) async {
    emit(UserLoading());
    
    final response = await _dio.get(
      'https://api.example.com/users/${event.id}',
      cancelToken: contextToken.toDio(), // ← конвертация
    );
    
    emit(UserLoaded(response.data));
  }
}
```

**Расширение автоматически:**
 - Синхронизирует состояние отмены между `ICancelToken` и Dio `CancelToken`
 - Пробрасывает причину отмены (reason) для отладки
 - Безопасно обрабатывает ситуации, когда токен уже отменён


## 📄 Лицензия
MIT © 2025

Это программное обеспечение распространяется под лицензией MIT.
.PHONY: help setup check build-all check-static

BUILDABLE = astro nextjs vite-react storage-shelf

help:
	@echo "layero-examples — примеры приложений на Layero"
	@echo ""
	@echo "  make check       — собираются все примеры + статика на месте"
	@echo "  make build-all   — сборка astro, nextjs, vite-react"
	@echo "  make check-static— в static-html есть что раздавать"
	@echo "  make setup       — npm ci во всех примерах со сборкой"

# ── Проверка ─────────────────────────────────────────────────────────────────
#
# Примеры — не только витрина, но и живой корпус: если пример перестал
# собираться, это сигнал о ПЛАТФОРМЕ, а не о примере. Поэтому `check` здесь
# именно сборка, и чинить её обходным путём нельзя — пример должен упасть
# честно, это его работа.
#
# Чего здесь НЕТ и почему:
#  · деплоя — `check` локальный; готовность примера доказывает только живой
#    адрес после `npx layero@latest deploy`;
#  · тестов — у примеров нет и не должно быть: они минимальны намеренно.

build-all:
	@set -e; for d in $(BUILDABLE); do \
		echo "── $$d"; (cd $$d && npm run build); \
	done

# Сборки нет — проверяем, что раздавать всё же есть что.
check-static:
	@test -s static-html/index.html || { \
		echo "FAIL: static-html/index.html пуст или отсутствует"; \
		echo "WHY:  пример без содержимого деплоится успешно и отдаёт пустую страницу —"; \
		echo "      отказ выглядит как успех и на витрине, и в корпусе."; \
		echo "FIX:  верните index.html либо уберите пример из репозитория."; \
		exit 1; }
	@echo "static-html: index.html на месте"

check: build-all check-static
	@echo ""
	@echo "✅ ALL CHECKS PASSED"

setup:
	@set -e; for d in $(BUILDABLE); do \
		echo "── $$d"; (cd $$d && npm ci); \
	done

PYTHON ?= python3
CL65 ?= cl65
CA65 ?= ca65
LD65 ?= ld65
GAME ?= invaders
GAMES := $(notdir $(wildcard games/*))
PLATFORM := $(wildcard platform/apple3/*.s) platform/apple3/game.cfg platform/apple3/apple3.h

.PHONY: all run test test-all clean
all: $(foreach game,$(GAMES),build/$(game)/$(game).po)

build/%/assets.s: games/%/sprites.json platform/apple3/font.json tools/assets.py
	$(PYTHON) tools/assets.py $< $(@D)

build/%/main.o: games/%/main.c build/%/assets.s $(wildcard platform/apple3/*.h) $(wildcard games/*/*.h)
	$(CL65) -t none --cpu 6502 -Oirs -g -I platform/apple3 -I $(@D) -c -o $@ $<

build/%/assets.o: build/%/assets.s
	$(CA65) -g -o $@ $<

build/platform/%.o: platform/apple3/%.s
	@mkdir -p $(@D)
	$(CA65) -g -o $@ $<

define GAME_RULES
build/$(1)/$(1).bin: build/$(1)/main.o build/$(1)/assets.o build/platform/startup.o build/platform/video.o build/platform/sound.o platform/apple3/game.cfg
	$$(CL65) -t none -C platform/apple3/game.cfg -m build/$(1)/$(1).map -Ln build/$(1)/$(1).lbl -Wl --dbgfile,build/$(1)/$(1).dbg -o $$@ $$(filter %.o,$$^)
build/$(1)/$(1).po: build/$(1)/$(1).bin platform/apple3/boot.s platform/apple3/boot.cfg tools/disk.py
	$$(PYTHON) tools/disk.py $$< --ca65 $$(CA65) --ld65 $$(LD65)
endef
$(foreach game,$(GAMES),$(eval $(call GAME_RULES,$(game))))

build/wordle/dictionary.h: games/wordle/words.txt games/wordle/answers.txt games/wordle/WORDLIST-LICENSE.txt tools/wordlist.py
	$(PYTHON) tools/wordlist.py games/wordle/words.txt games/wordle/answers.txt $@

build/wordle/main.o: build/wordle/dictionary.h

run: build/$(GAME)/$(GAME).po
	$(PYTHON) tools/mame.py run $(GAME)

test: all
	$(PYTHON) -m unittest discover -s tests -p 'test_*.py'
	$(PYTHON) tools/mame.py test $(GAME)

test-all: all
	$(PYTHON) -m unittest discover -s tests -p 'test_*.py'
	@for game in $(GAMES); do $(PYTHON) tools/mame.py test $$game || exit $$?; done

clean:
	$(PYTHON) -c "import shutil; from pathlib import Path; [shutil.rmtree(p) for p in Path('build').glob('*') if p.is_dir() and p.name != 'local-roms']"

.SECONDARY:

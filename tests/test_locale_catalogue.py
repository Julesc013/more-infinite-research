"""Independent coverage for retained MIR research locale entries."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1]
LOCALE_ROOT = ROOT / "source" / "locale"
PUBLISHED_B6_ARCHIVE_SHA256 = "B6EB9430056ABD384DB00F94929FE7DAC0A37441ACF4BC277946689682628852"
NEW_ENGLISH_ONLY_KEY = "more-infinite-research.recipe_productivity"
NEW_ENGLISH_ONLY_VALUE = "Recipe productivity"
DIRECT_EFFECT_KEY = "technology-description.more-infinite-research.direct_effect"
REFERENCE_PATTERN = re.compile(
    r"(?P<section>technology-name|technology-description|modifier-description)\.more-infinite-research\.(?P<key>[a-z0-9_]+)"
)

# These are the finite active source references present in B6. The per-locale
# projected hashes below pin their historical values without making a local B6
# archive a CI dependency.
B6_RETAINED_KEYS = {
    'modifier-description': (
        'more-infinite-research.agricultural_growth_speed',
        'more-infinite-research.spoilage_preservation',
    ),
    'technology-description': (
        'more-infinite-research.agricultural_growth_speed',
        'more-infinite-research.cargo_bay_unloading_distance',
        'more-infinite-research.cargo_landing_pad_count',
        'more-infinite-research.direct_effect',
        'more-infinite-research.electric_shooting_speed',
        'more-infinite-research.flamethrower_shooting_speed',
        'more-infinite-research.lab_productivity',
        'more-infinite-research.recipe_productivity',
        'more-infinite-research.spoilage_preservation',
    ),
    'technology-name': (
        'more-infinite-research.research_advanced_circuit',
        'more-infinite-research.research_agricultural_growth_speed',
        'more-infinite-research.research_armor_components',
        'more-infinite-research.research_artificial_soil',
        'more-infinite-research.research_bacteria_cultivation',
        'more-infinite-research.research_batteries',
        'more-infinite-research.research_belts',
        'more-infinite-research.research_bioflux',
        'more-infinite-research.research_breeding',
        'more-infinite-research.research_bullets',
        'more-infinite-research.research_cannon_shooting_speed',
        'more-infinite-research.research_capture_robot_rockets',
        'more-infinite-research.research_carbon',
        'more-infinite-research.research_carbon_fiber',
        'more-infinite-research.research_cargo_bay_unloading_distance',
        'more-infinite-research.research_cargo_landing_pad_count',
        'more-infinite-research.research_character_crafting_speed',
        'more-infinite-research.research_character_mining_speed',
        'more-infinite-research.research_character_reach',
        'more-infinite-research.research_character_walking_speed',
        'more-infinite-research.research_concrete',
        'more-infinite-research.research_copper',
        'more-infinite-research.research_copper_cable',
        'more-infinite-research.research_electric_energy',
        'more-infinite-research.research_electric_engine',
        'more-infinite-research.research_electric_shooting_speed',
        'more-infinite-research.research_electronic_circuit',
        'more-infinite-research.research_engine',
        'more-infinite-research.research_explosives',
        'more-infinite-research.research_flamethrower_shooting_speed',
        'more-infinite-research.research_flying_robot_frame',
        'more-infinite-research.research_furnace',
        'more-infinite-research.research_gears',
        'more-infinite-research.research_grenades',
        'more-infinite-research.research_heavy_ammo',
        'more-infinite-research.research_holmium',
        'more-infinite-research.research_ice',
        'more-infinite-research.research_inserters',
        'more-infinite-research.research_inventory_capacity',
        'more-infinite-research.research_iron',
        'more-infinite-research.research_iron_sticks',
        'more-infinite-research.research_lab_productivity',
        'more-infinite-research.research_landfill',
        'more-infinite-research.research_lithium',
        'more-infinite-research.research_low_density_structure',
        'more-infinite-research.research_lubricant_productivity',
        'more-infinite-research.research_mining_drill',
        'more-infinite-research.research_modules',
        'more-infinite-research.research_molten_metals',
        'more-infinite-research.research_nutrients',
        'more-infinite-research.research_oil_cracking_productivity',
        'more-infinite-research.research_oil_processing_productivity',
        'more-infinite-research.research_plastic',
        'more-infinite-research.research_platform',
        'more-infinite-research.research_processing_unit',
        'more-infinite-research.research_quantum_processor',
        'more-infinite-research.research_rails',
        'more-infinite-research.research_robot_battery',
        'more-infinite-research.research_rocket_fuel',
        'more-infinite-research.research_rocket_shooting_speed',
        'more-infinite-research.research_rockets',
        'more-infinite-research.research_science_pack_productivity',
        'more-infinite-research.research_spoilage_preservation',
        'more-infinite-research.research_steel',
        'more-infinite-research.research_sulfur',
        'more-infinite-research.research_sulfuric_acid_productivity',
        'more-infinite-research.research_supercapacitor',
        'more-infinite-research.research_superconductor',
        'more-infinite-research.research_thruster_fuel_productivity',
        'more-infinite-research.research_thruster_oxidizer_productivity',
        'more-infinite-research.research_tungsten',
        'more-infinite-research.research_walls',
    ),
}

# The current laboratory wording intentionally superseded the older B6 wording;
# keep it rather than overwriting an existing translation during restoration.
CURRENT_TRANSLATION_OVERRIDES = {
    'de': {
        'technology-name.more-infinite-research.research_lab_productivity': 'Laborproduktivität',
    },
    'en': {
        'technology-name.more-infinite-research.research_lab_productivity': 'Laboratory productivity',
    },
}

# Accepted meaning corrections retain each reviewed current literal before normalizing
# only that value to its historical B6 literal; the complete historical projection stays pinned.
# The Russian corrections below originate in AstardGrimoire/more-infinite-research
# commit 389a8b848145a89713be32b658c80113565246b4, locale/ru/more-infinite-research.cfg.
# Direct-effect #1768 uses the raw source/locale/<language>/more-infinite-research.cfg
# blobs from published v5.0.10 commit 958e34dd2701418c71f74ae094c26ff7cd467e6b:
# each pair preserves that translation's original first benefit sentence and restores
# only the removed active-lab-science suffix while normalizing the B6 projection.
ACCEPTED_POST_B6_CORRECTIONS = {
    'ru': {
        'technology-name.more-infinite-research.research_heavy_ammo': (
            'Продуктивность пушечных снарядов', 'Производительность артиллерийского снаряда',
        ),
        'technology-name.more-infinite-research.research_thruster_fuel_productivity': (
            'Продуктивность топлива для ускорителя', 'Расход топлива двигателя',
        ),
        'technology-name.more-infinite-research.research_thruster_oxidizer_productivity': (
            'Продуктивность окислителя для ускорителя', 'Производительность двигателя окислителя',
        ),
        # Additional contributor wording independently reconciled in CONT-16
        # (semantic review 3E5BB8AC). Preserve the original B6 projection below.
        'technology-name.more-infinite-research.research_agricultural_growth_speed': (
            'Скорость роста растений', 'Скорость роста сельского хозяйства',
        ),
        'technology-name.more-infinite-research.research_lab_productivity': (
            'Продуктивность лабораторий', 'Продуктивность исследований',
        ),
        'technology-name.more-infinite-research.research_lubricant_productivity': (
            'Продуктивность смазочной жидкости', 'Производительность смазки',
        ),
        'technology-name.more-infinite-research.research_oil_cracking_productivity': (
            'Продуктивность крекинга нефтепродуктов', 'Производительность крекинга нефти',
        ),
        'technology-name.more-infinite-research.research_oil_processing_productivity': (
            'Продуктивность переработки нефти', 'Производительность нефтепереработки',
        ),
        'technology-name.more-infinite-research.research_sulfuric_acid_productivity': (
            'Продуктивность серной кислоты', 'Производительность серной кислоты',
        ),
        'technology-description.more-infinite-research.spoilage_preservation': (
            'Увеличивает глобальный модификатор времени порчи посредством ограниченного скриптового эффекта. '
            'Существующие портящиеся предметы могут сохранять текущие сроки порчи до проверки в игре.',
            'Увеличивает глобальный модификатор времени порчи посредством ограниченного скриптового эффекта. '
            'Существующие портимые предметы могут сохранять текущие сроки порчи до тех пор, пока не будут проверены в игре.',
        ),
        'technology-description.more-infinite-research.agricultural_growth_speed': (
            'Сокращает оставшееся время роста недавно посаженных сельскохозяйственными башнями растений '
            'посредством ограниченного скриптового эффекта.',
            'Сокращает оставшееся время роста недавно посаженных сельскохозяйственных башенных растений '
            'за счет ограниченного скриптового эффекта.',
        ),
        'technology-description.more-infinite-research.electric_shooting_speed': (
            'Увеличивает скорость стрельбы электрического оружия. В базовой игре это влияет на электроразрядную защиту; '
            'со Space Age это также влияет на оружие Теслы, если доступна категория боеприпасов Теслы.',
            'Увеличивает скорость стрельбы из электрического оружия. В ванили это влияет на защиту от разряда; '
            'в Space Age это также влияет на оружие Tesla, если доступна категория боеприпасов Tesla.',
        ),
        'modifier-description.more-infinite-research.agricultural_growth_speed': (
            'Скорость роста растений: +__1__% за уровень.',
            'Скорость роста сельского хозяйства: +__1__% за уровень.',
        ),
        'technology-description.more-infinite-research.direct_effect': (
            "Добавляет бесконечно повторяемый бонус.", "Добавляет бесконечно повторяемый бонус. Исследовательские пакеты выбираются из активных лабораторий, чтобы технология оставалась исследуемой с совместимыми наборами модов.",
        ),
    },
    'af': {
        'technology-description.more-infinite-research.direct_effect': (
            "Voeg 'n oneindige herhaalbare bonus by.", "Voeg 'n oneindige herhaalbare bonus by. Wetenskappakkette word uit aktiewe laboratoriums gekies, sodat die tegnologie navorsbaar bly met versoenbare mod-stelle.",
        ),
    },
    'ar': {
        'technology-description.more-infinite-research.direct_effect': (
            "يضيف مكافأة لا حصر لها قابلة للتكرار.", "يضيف مكافأة لا حصر لها قابلة للتكرار. يتم اختيار حزم العلوم من المعامل النشطة بحيث تظل التكنولوجيا قابلة للبحث باستخدام مجموعات التعديل المتوافقة.",
        ),
    },
    'be': {
        'technology-description.more-infinite-research.direct_effect': (
            "Дадае бясконцы паўторны бонус.", "Дадае бясконцы паўторны бонус. Навуковыя пакеты выбіраюцца з дзеючых лабараторый, таму тэхналогія застаецца даступнай для даследавання з дапамогай сумяшчальных набораў модаў.",
        ),
    },
    'bg': {
        'technology-description.more-infinite-research.direct_effect': (
            "Добавя безкраен повторяем бонус.", "Добавя безкраен повторяем бонус. Научните пакети се избират от активни лаборатории, така че технологията остава изследваема със съвместими комплекти модове.",
        ),
    },
    'ca': {
        'technology-description.more-infinite-research.direct_effect': (
            "Afegeix una bonificació repetible infinita.", "Afegeix una bonificació repetible infinita. Els paquets de ciència es seleccionen dels laboratoris actius, de manera que la tecnologia segueix sent investigable amb conjunts de modificacions compatibles.",
        ),
    },
    'cs': {
        'technology-description.more-infinite-research.direct_effect': (
            "Přidá nekonečný opakovatelný bonus.", "Přidá nekonečný opakovatelný bonus. Vědecké balíčky jsou vybírány z aktivních laboratoří, takže technologii lze zkoumat pomocí kompatibilních sad modů.",
        ),
    },
    'da': {
        'technology-description.more-infinite-research.direct_effect': (
            "Tilføjer en uendelig gentagelig bonus.", "Tilføjer en uendelig gentagelig bonus. Science packs er udvalgt fra aktive laboratorier, så teknologien forbliver researchbar med kompatible modsæt.",
        ),
    },
    'de': {
        # R07 visual review: use the native 2.1.23 Space Age item/recipe noun
        # "Rakete fuer Gefangennahme" while retaining the original B6 literal.
        'technology-name.more-infinite-research.research_capture_robot_rockets': (
            'Produktivität von Raketen für Gefangennahme',
            'Erfassen Sie die Produktivität von Bot-Raketen',
        ),
        'technology-description.more-infinite-research.direct_effect': (
            "Fügt einen unendlich wiederholbaren Bonus hinzu.", "Fügt einen unendlich wiederholbaren Bonus hinzu. Wissenschaftspakete werden aus aktiven Laboren ausgewählt, damit die Technologie mit kompatiblen Mod-Sätzen erforschbar bleibt.",
        ),
    },
    'el': {
        'technology-description.more-infinite-research.direct_effect': (
            "Προσθέτει ένα άπειρο επαναλαμβανόμενο μπόνους.", "Προσθέτει ένα άπειρο επαναλαμβανόμενο μπόνους. Τα επιστημονικά πακέτα επιλέγονται από ενεργά εργαστήρια, ώστε η τεχνολογία να παραμένει ερευνήσιμη με συμβατά σετ mod.",
        ),
    },
    'en': {
        'technology-description.more-infinite-research.direct_effect': (
            "Adds an infinite repeatable bonus.", "Adds an infinite repeatable bonus. Science packs are selected from active labs so the technology remains researchable with compatible mod sets.",
        ),
    },
    'eo': {
        'technology-description.more-infinite-research.direct_effect': (
            "Aldonas senfinan ripeteblan gratifikon.", "Aldonas senfinan ripeteblan gratifikon. Sciencaj pakoj estas elektitaj el aktivaj laboratorioj, do la teknologio restas esplorebla kun kongruaj mod-aroj.",
        ),
    },
    'es-ES': {
        'technology-description.more-infinite-research.direct_effect': (
            "Añade una bonificación infinita repetible.", "Añade una bonificación infinita repetible. Los paquetes de ciencia se seleccionan a partir de los laboratorios activos para que la tecnología siga siendo investigable con conjuntos de mods compatibles.",
        ),
    },
    'et': {
        'technology-description.more-infinite-research.direct_effect': (
            "Lisab lõputu korratava boonuse.", "Lisab lõputu korratava boonuse. Teaduspaketid valitakse aktiivsetest laboritest, nii et tehnoloogia on ühilduvate modikomplektidega uuritav.",
        ),
    },
    'eu': {
        'technology-description.more-infinite-research.direct_effect': (
            "Hobari errepikagarri infinitua gehitzen du.", "Hobari errepikagarri infinitua gehitzen du. Zientzia-paketeak laborategi aktiboetatik hautatzen dira, teknologiak mod-multzo bateragarriekin ikertu ahal izateko.",
        ),
    },
    'fa': {
        'technology-description.more-infinite-research.direct_effect': (
            "یک جایزه قابل تکرار بی نهایت اضافه می کند.", "یک جایزه قابل تکرار بی نهایت اضافه می کند. بسته‌های علمی از آزمایشگاه‌های فعال انتخاب می‌شوند، بنابراین فناوری با مجموعه‌های مد سازگار قابل تحقیق باقی می‌ماند.",
        ),
    },
    'fi': {
        'technology-description.more-infinite-research.direct_effect': (
            "Lisää loputtoman toistettavan bonuksen.", "Lisää loputtoman toistettavan bonuksen. Tiedepaketit valitaan aktiivisista laboratorioista, joten tekniikka pysyy tutkittavissa yhteensopivien mod-sarjojen kanssa.",
        ),
    },
    'fil': {
        'technology-description.more-infinite-research.direct_effect': (
            "Nagdaragdag ng walang katapusang nauulit na bonus.", "Nagdaragdag ng walang katapusang nauulit na bonus. Pinipili ang mga science pack mula sa mga aktibong lab upang manatiling masasaliksik ang teknolohiya sa mga katugmang mod set.",
        ),
    },
    'fr': {
        'technology-description.more-infinite-research.direct_effect': (
            "Ajoute un bonus répétable à l'infini.", "Ajoute un bonus répétable à l'infini. Les packs de science sont choisis à partir des laboratoires actifs afin que la technologie reste recherchable avec les ensembles de mods compatibles.",
        ),
    },
    'fy-NL': {
        'technology-description.more-infinite-research.direct_effect': (
            "Foeget in ûneinige werhelle bonus ta.", "Foeget in ûneinige werhelle bonus ta. Wittenskipspakketten wurde selektearre út aktive laboratoaren, sadat de technology ûndersiikber bliuwt mei kompatibele mod-sets.",
        ),
    },
    'ga-IE': {
        'technology-description.more-infinite-research.direct_effect': (
            "Cuirtear bónas in-athdhéanta gan teorainn leis.", "Cuirtear bónas in-athdhéanta gan teorainn leis. Roghnaítear pacáistí eolaíochta ó shaotharlanna gníomhacha agus mar sin is féidir taighde a dhéanamh ar an teicneolaíocht le tacair modúil comhoiriúnacha.",
        ),
    },
    'he': {
        'technology-description.more-infinite-research.direct_effect': (
            "מוסיף בונוס אינסופי שניתן לחזור עליו.", "מוסיף בונוס אינסופי שניתן לחזור עליו. ערכות מדע נבחרות ממעבדות פעילות כך שהטכנולוגיה נשארת ניתנת למחקר עם ערכות מוד תואמות.",
        ),
    },
    'hr': {
        'technology-description.more-infinite-research.direct_effect': (
            "Dodaje beskonačni ponovljivi bonus.", "Dodaje beskonačni ponovljivi bonus. Znanstveni paketi biraju se iz aktivnih laboratorija tako da se tehnologija može istražiti s kompatibilnim setovima modifikacija.",
        ),
    },
    'hu': {
        'technology-description.more-infinite-research.direct_effect': (
            "Végtelen megismételhető bónuszt ad hozzá.", "Végtelen megismételhető bónuszt ad hozzá. A tudományos csomagokat az aktív laborokból választják ki, így a technológia kutatható marad a kompatibilis modkészletekkel.",
        ),
    },
    'id': {
        'technology-description.more-infinite-research.direct_effect': (
            "Menambahkan bonus berulang yang tak terbatas.", "Menambahkan bonus berulang yang tak terbatas. Paket sains dipilih dari laboratorium aktif sehingga teknologinya tetap dapat diteliti dengan set mod yang kompatibel.",
        ),
    },
    'is': {
        'technology-description.more-infinite-research.direct_effect': (
            "Bætir við óendanlega endurteknum bónus.", "Bætir við óendanlega endurteknum bónus. Vísindapakkar eru valdir úr virkum rannsóknarstofum þannig að tæknin er áfram rannsóknarhæf með samhæfum mod settum.",
        ),
    },
    'it': {
        'technology-description.more-infinite-research.direct_effect': (
            "Aggiunge un bonus ripetibile all'infinito.", "Aggiunge un bonus ripetibile all'infinito. I pacchetti scientifici vengono scelti dai laboratori attivi, così la tecnologia rimane ricercabile con set di mod compatibili.",
        ),
    },
    'ja': {
        'technology-description.more-infinite-research.direct_effect': (
            "無限に繰り返し可能なボーナスを追加します。", "無限に繰り返し可能なボーナスを追加します。サイエンス パックはアクティブなラボから選択されるため、テクノロジーは互換性のある MOD セットで引き続き研究可能です。",
        ),
    },
    'ka': {
        'technology-description.more-infinite-research.direct_effect': (
            "ამატებს უსასრულო განმეორებად ბონუსს.", "ამატებს უსასრულო განმეორებად ბონუსს. სამეცნიერო პაკეტები შერჩეულია აქტიური ლაბორატორიებიდან, ასე რომ, ტექნოლოგია რჩება შესასწავლად თავსებადი მოდების კომპლექტებით.",
        ),
    },
    'kk': {
        'technology-description.more-infinite-research.direct_effect': (
            "Шексіз қайталанатын бонус қосады.", "Шексіз қайталанатын бонус қосады. Ғылыми жинақтар белсенді зертханалардан таңдалады, сондықтан технология үйлесімді мод жиынтықтарымен зерттелетін болып қалады.",
        ),
    },
    'ko': {
        'technology-description.more-infinite-research.direct_effect': (
            "무한 반복 보너스를 추가합니다.", "무한 반복 보너스를 추가합니다. 과학 팩은 활성 실험실에서 선택되므로 해당 기술은 호환 가능한 모드 세트로 계속 연구할 수 있습니다.",
        ),
    },
    'lt': {
        'technology-description.more-infinite-research.direct_effect': (
            "Prideda begalinę pakartojamą premiją.", "Prideda begalinę pakartojamą premiją. Mokslo paketai parenkami iš aktyvių laboratorijų, todėl technologiją galima ištirti naudojant suderinamus modifikacijų rinkinius.",
        ),
    },
    'lv': {
        'technology-description.more-infinite-research.direct_effect': (
            "Pievieno bezgalīgu atkārtojamu bonusu.", "Pievieno bezgalīgu atkārtojamu bonusu. Zinātnes pakotnes ir atlasītas no aktīvām laboratorijām, tāpēc tehnoloģija joprojām ir pētāma ar saderīgiem moduļu komplektiem.",
        ),
    },
    'nl': {
        'technology-description.more-infinite-research.direct_effect': (
            "Voegt een oneindig herhaalbare bonus toe.", "Voegt een oneindig herhaalbare bonus toe. Wetenschapspakketten worden geselecteerd uit actieve laboratoria, zodat de technologie onderzoekbaar blijft met compatibele mod-sets.",
        ),
    },
    'no': {
        'technology-description.more-infinite-research.direct_effect': (
            "Legger til en uendelig repeterbar bonus.", "Legger til en uendelig repeterbar bonus. Vitenskapspakker er valgt fra aktive laboratorier, slik at teknologien forblir forskningbar med kompatible mod-sett.",
        ),
    },
    'pl': {
        'technology-description.more-infinite-research.direct_effect': (
            "Dodaje nieskończenie powtarzalną premię.", "Dodaje nieskończenie powtarzalną premię. Pakiety naukowe są wybierane z aktywnych laboratoriów, aby technologia pozostała możliwa do zbadania z kompatybilnymi zestawami modów.",
        ),
    },
    'pt-BR': {
        'technology-description.more-infinite-research.direct_effect': (
            "Adiciona um bônus infinito repetível.", "Adiciona um bônus infinito repetível. Os pacotes científicos são selecionados a partir dos laboratórios ativos para que a tecnologia continue pesquisável com conjuntos de mods compatíveis.",
        ),
    },
    'pt-PT': {
        'technology-description.more-infinite-research.direct_effect': (
            "Adiciona um bônus repetível infinito.", "Adiciona um bônus repetível infinito. Os pacotes científicos são selecionados em laboratórios ativos para que a tecnologia permaneça pesquisável com conjuntos de mods compatíveis.",
        ),
    },
    'ro': {
        'technology-description.more-infinite-research.direct_effect': (
            "Adaugă un bonus repetabil infinit.", "Adaugă un bonus repetabil infinit. Pachetele științifice sunt selectate din laboratoarele active, astfel încât tehnologia rămâne cercetabilă cu seturi de mod compatibile.",
        ),
    },
    'sk': {
        'technology-description.more-infinite-research.direct_effect': (
            "Pridáva nekonečný opakovateľný bonus.", "Pridáva nekonečný opakovateľný bonus. Vedecké balíčky sa vyberajú z aktívnych laboratórií, takže technológia zostáva skúmateľná pomocou kompatibilných súprav modov.",
        ),
    },
    'sl': {
        'technology-description.more-infinite-research.direct_effect': (
            "Doda neskončen ponovljiv bonus.", "Doda neskončen ponovljiv bonus. Znanstveni paketi so izbrani iz aktivnih laboratorijev, tako da je tehnologija še vedno raziskljiva z združljivimi sklopi modov.",
        ),
    },
    'sq': {
        'technology-description.more-infinite-research.direct_effect': (
            "Shton një bonus të pafund të përsëritshëm.", "Shton një bonus të pafund të përsëritshëm. Paketat shkencore zgjidhen nga laboratorë aktivë, në mënyrë që teknologjia të mbetet e kërkueshme me grupe modash të përputhshme.",
        ),
    },
    'sr': {
        'technology-description.more-infinite-research.direct_effect': (
            "Додаје бесконачан поновљив бонус.", "Додаје бесконачан поновљив бонус. Научни пакети се бирају из активних лабораторија, тако да се технологија може истражити са компатибилним сетовима модова.",
        ),
    },
    'sv-SE': {
        'technology-description.more-infinite-research.direct_effect': (
            "Lägger till en oändlig upprepningsbar bonus.", "Lägger till en oändlig upprepningsbar bonus. Vetenskapspaket väljs från aktiva laboratorier så att tekniken förblir forskningsbar med kompatibla mod-set.",
        ),
    },
    'th': {
        'technology-description.more-infinite-research.direct_effect': (
            "เพิ่มโบนัสที่ทำซ้ำได้ไม่สิ้นสุด", "เพิ่มโบนัสที่ทำซ้ำได้ไม่สิ้นสุด ชุดวิทยาศาสตร์ได้รับการคัดเลือกจากห้องปฏิบัติการที่ใช้งานอยู่ ดังนั้นเทคโนโลยีจึงสามารถวิจัยได้ด้วยชุดม็อดที่เข้ากันได้",
        ),
    },
    'tr': {
        'technology-description.more-infinite-research.direct_effect': (
            "Sonsuz tekrarlanabilir bonus ekler.", "Sonsuz tekrarlanabilir bonus ekler. Bilim paketleri aktif laboratuvarlardan seçilir, böylece teknoloji uyumlu mod setleriyle araştırılabilir kalır.",
        ),
    },
    'uk': {
        'technology-description.more-infinite-research.direct_effect': (
            "Додає нескінченний повторюваний бонус.", "Додає нескінченний повторюваний бонус. Наукові пакети вибираються з активних лабораторій, тому технологію можна досліджувати за допомогою сумісних наборів модів.",
        ),
    },
    'vi': {
        'technology-description.more-infinite-research.direct_effect': (
            "Thêm phần thưởng có thể lặp lại vô hạn.", "Thêm phần thưởng có thể lặp lại vô hạn. Các gói khoa học được chọn từ các phòng thí nghiệm đang hoạt động nên công nghệ vẫn có thể nghiên cứu được với các bộ mod tương thích.",
        ),
    },
    'zh-CN': {
        'technology-description.more-infinite-research.direct_effect': (
            "添加无限可重复的奖励。", "添加无限可重复的奖励。科学包是从活跃的实验室中选择的，因此该技术仍然可以通过兼容的模组集进行研究。",
        ),
    },
    'zh-TW': {
        'technology-description.more-infinite-research.direct_effect': (
            "添加無限可重複的獎勵。", "添加無限可重複的獎勵。科學包是從活躍的實驗室中選擇的，因此該技術仍然可以透過相容的模組集進行研究。",
        ),
    },
}

EXPECTED_RETAINED_PROJECTION_SHA256 = {
    'af': 'CB8F1EEEEBA24911BAC1E2B4A909C6698736BE14F50734D57EB86E86BD4F3817',
    'ar': '09F2DD177C5A1F1660E7456B895B01723E0ED93F1B924D7539CDCD492CAFDCDE',
    'be': '7B90B6A5B398078C0D129C61A80F4592065A74CEB70D23A0D58AC4186635ACD9',
    'bg': 'ACF1BD6CD53BADEA0C846D95A34E8E362F93B8F17290AE151EE8BE5EE3428667',
    'ca': '8518017BBC531975B95EC2E51A51C24CDBFB708FF7FC08F46176DF93AB76EE36',
    'cs': 'F1AC9E1D846B019FEB48250265F47E119C59CE83927B681F27BBAC9BB71DF748',
    'da': '2311136C0A32F7B634883B1C64E270C2B0CFE02763D210C6EB5CA13F3966B34F',
    'de': '7D20D8F6B0F5F3940F281B00166991DEFB6FB11B2B9EC5756E175FE008B53745',
    'el': 'A55E1BDA8B3ADBB87A8FC1FDB5BADB388F257FAD9AB878F4898D6663FD85A3D3',
    'en': 'A603DADA9F23D75D5F33856440A9EDDA4F130936ACE5FCEFD37C8E58BE1BD5E9',
    'eo': '71921D7C3E3BA33AC66C9D210D2DED284D63FE27F045120E48A62D1E8C5C2E15',
    'es-ES': '90CF7F1A69A6B8752FCFC941DE4D03B0DA64912BE46A8718AF1BAFF414544414',
    'et': '06EAEAB3503214555D78DF2DC605D00C5DE4448E49214DFC98E4DC79D542486F',
    'eu': 'C8882CB42E037001CDFB32F05FE12A4FAEC2EF76F5794FB8E814D33BD9956B67',
    'fa': '2A63E43A51C4E8A69080CF3EC4EDF358EDA123856342241D62BB81979C60B9F2',
    'fi': '9CC78CD89DF4EC1144F7E918C5880EF8E62EA1EC5FCF5FF3309703B6371DF204',
    'fil': '8CBCF20F5AA737D1CEF561095F7A11BE6C74EF1EB423F8FCABC0B2ED35474A62',
    'fr': '9DAEF3458BC060FB69412F0672244543BCDB987D6F8EA6B6761DAB68A56B9D50',
    'fy-NL': '1605F30FA7620E67D67D813A88A44C6C8AD5613C8E6AA7AC0D4860E56A4E0BE7',
    'ga-IE': 'C92FF4B81D54BB28074AC146C7CA57D4CBE6DF3DD9C2FF40DA99EA9715CAE46B',
    'he': '8174E925CFD3D98F1E035D3164FBB40EC57A21C14C935D567FB28EDBA7CCE8F2',
    'hr': '890D9DA4DF192208C7BD25156F3ABFC50F3F3F0E4AA164F60C9DB08CDC5E558E',
    'hu': '819C4CD6CECAA50B1A31CC7222DFD7C24234E1B0B25CF67724148C9ACAFAB907',
    'id': 'B405C2950D47C3C08D42361164A127792806017EAE5E6E0D00EA3F78C5A780EA',
    'is': '7B43E6F532BEC0355ED1324ACF778CA957E75C3997541714B8D535D08AB04CDD',
    'it': 'C9C2D427501DF1FE54DB31C29789F673BE36223F754FA54667500C54EDBC7FC6',
    'ja': 'AB0ABD17FEC65EB343D28ED078B6CCBF0CE08C39E4A36504603ABCFBB7979723',
    'ka': 'AAFE6E67C125E0F0E67A1713044FE46E6B54D991B4A0CA8A85F3FC4D52B26C50',
    'kk': '0FC50462889B96240437B2E556FB71A105CACDBA8827198618FB5A56469F39BB',
    'ko': 'F938535D339FE0D65FEDDDB181B0C70AC8D51E3D6920934F1D1FA4B95E8D2815',
    'lt': '94E3DB188CE77886C757AD0800B8B3D07BF54CE74A61527B22503FC16087EFD0',
    'lv': '3F61CF90C2E27641DECDE4916C0C82E3BFC89BE58BDC177D60052B448455D2CB',
    'nl': '31727286BB1F7CE558D37E25D4E1C99F7D2E9F779F07DD32CB66CD37B8DE5C8B',
    'no': '5E7C0564458ADAD81B408417CF92C712AAD2845BB701975A54C3D8CCCDE703D8',
    'pl': '55E5004657EC7B7DCA4B6C91F25B6B5698EECE1E0D47132124D1D62ADC336A5E',
    'pt-BR': '1F81CC41E3465FCF632F4D2C2A1F4E300028E16DC97301847E4F88F253F2180A',
    'pt-PT': '3C118F4D81A5DE56E1AFC7F22D454017B7B194E31CBD7687572AEC14EFDDD43C',
    'ro': '56FDC6E14938315503985D118F59792C4323777F7E973756010A96DCA36F719D',
    'ru': 'DAE9832ED1B0D853898057B67AAFB29026A6A24AEB5D8B9597366368CFFD3BD1',
    'sk': 'D44A4C05E2C7AA67D218EFC32D9E6A37D3300D66951727F5718CE55B51BAEBB2',
    'sl': 'A6C8EFF7271E505A98A0FD56E964DCED2331BDBF7018CAD76C6441FC5953A073',
    'sq': 'BE6D35925B920939EDED7C0EC2F4609765FDA5F88098D63EAB0ECE09EED6870E',
    'sr': 'F228A108183FD797EB0F8B0E74EC217901273FF0E1A2E7BB4629BE5D7F999993',
    'sv-SE': '6C9D2C9D604F41DCBC652E8997CACAAD0460D6EEBDAB5B1D19E66C55E7E69C9E',
    'th': '4E0EABD5D6BCED1B66888E36176A101A364173F8FB32C968C4554955246A43F9',
    'tr': '50E9B3A18D7A90D5C97EEEF1215B16FB04EE17031F04C82CB7B9ABF18DEC8B99',
    'uk': 'A682B1DEB648AEED69E1947438ADB2A889C55CF9EE30EB9987B55C3E984488B7',
    'vi': 'A483C872173877CB51AB890F5FD6FF4D6926F2BEC1BF252D46A95CE72243F1AE',
    'zh-CN': '8F61CAEC02245B9BEF692405A42CA5E7FAEEDAA0EE22C0466F8964B8302A0354',
    'zh-TW': '52F95F49CE30190437EEBAA6B4D38999E3F0BA3E94EB692B27E936CE5CBBA5DD',
}

# These are the finite current material families which the Library availability
# view constructs through `row.family`. They have no B6 locale entries, so the
# English labels below are explicitly new display corrections rather than
# recovered translations.
COMPUTED_MATERIAL_FAMILY_SOURCES = (
    "source/presentation/availability.lua",
    "source/research/bob_angel_materials.lua",
    "source/research/bob_core_materials.lua",
    "source/research/bob_plates_materials.lua",
    "source/research/k2_imersite.lua",
    "source/research/k2_materials.lua",
    "source/research/py_materials.lua",
)
COMPUTED_MATERIAL_FAMILY_PATTERN = re.compile(r"research_material_[a-z_]+")
COMPUTED_MATERIAL_ENGLISH_NAMES = {
    "research_material_aluminium": "Aluminium productivity",
    "research_material_brass": "Brass productivity",
    "research_material_bronze": "Bronze productivity",
    "research_material_cobalt_steel": "Cobalt steel productivity",
    "research_material_copper_tungsten": "Copper tungsten productivity",
    "research_material_glass": "Glass productivity",
    "research_material_gold": "Gold productivity",
    "research_material_gunmetal": "Gunmetal productivity",
    "research_material_imersite": "Imersite productivity",
    "research_material_invar": "Invar productivity",
    "research_material_lead": "Lead productivity",
    "research_material_nickel": "Nickel productivity",
    "research_material_nitinol": "Nitinol productivity",
    "research_material_platinum": "Platinum productivity",
    "research_material_py_log": "Log productivity",
    "research_material_rare_metals": "Rare metals productivity",
    "research_material_silicon": "Silicon productivity",
    "research_material_silver": "Silver productivity",
    "research_material_tin": "Tin productivity",
    "research_material_titanium": "Titanium productivity",
    "research_material_zinc": "Zinc productivity",
}


def parse_cfg_text(text: str, label: str) -> dict[str, dict[str, str]]:
    sections: dict[str, dict[str, str]] = {}
    current: str | None = None
    for line_number, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.strip()
        if not line or line.startswith(";"):
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1]
            sections.setdefault(current, {})
            continue
        if current is None or "=" not in raw_line:
            continue
        key, value = raw_line.split("=", 1)
        if key in sections[current]:
            raise ValueError(f"duplicate locale key {current}.{key} at {label}:{line_number}")
        sections[current][key] = value
    return sections


def parse_cfg(path: Path) -> dict[str, dict[str, str]]:
    return parse_cfg_text(path.read_text(encoding="utf-8"), str(path))


def active_source_references() -> set[str]:
    references: set[str] = set()
    for path in (ROOT / "source").rglob("*.lua"):
        for match in REFERENCE_PATTERN.finditer(path.read_text(encoding="utf-8")):
            references.add(f"{match.group('section')}.more-infinite-research.{match.group('key')}")
    return references


def computed_material_families() -> set[str]:
    families: set[str] = set()
    for relative_path in COMPUTED_MATERIAL_FAMILY_SOURCES:
        text = (ROOT / relative_path).read_text(encoding="utf-8")
        for match in COMPUTED_MATERIAL_FAMILY_PATTERN.finditer(text):
            family = match.group(0)
            if not family.endswith("__continuation"):
                families.add(family)
    return families


def retained_projection(sections: dict[str, dict[str, str]]) -> dict[str, str]:
    projection: dict[str, str] = {}
    for section, keys in B6_RETAINED_KEYS.items():
        for key in keys:
            projection[f"{section}.{key}"] = sections[section][key]
    return projection


def direct_effect_first_benefit(language: str, historical: str) -> str:
    if language == "th":
        first_benefit, separator, _ = historical.partition(" ชุดวิทยาศาสตร์")
        if not separator:
            raise ValueError(f"missing Thai direct-effect benefit boundary: {language}")
        return first_benefit
    delimiter = "。" if language in {"ja", "zh-CN", "zh-TW"} else "."
    first_benefit, separator, _ = historical.partition(delimiter)
    if not separator:
        raise ValueError(f"missing direct-effect benefit boundary: {language}")
    return first_benefit + separator


# Published 4.7.3 English keys, restricted to current native locale map and
# current standalone declarations. Native descriptors supply one technology argument.
NATIVE_SETTING_KEYS = (
    "mir-enable-base-tech", "mir-cost-base", "mir-cost-linear-increment",
    "mir-cost-growth", "mir-max-level", "mir-research-time", "mir-effect-per-level",
)
STANDALONE_SETTING_KEYS = (
    "ips-require-space-gate", "mir-science-pack-ingredient-policy",
    "mir-prefer-this-mod-for-competing-techs", "mir-use-installed-space-age-icons",
)


class LocaleCatalogueTests(unittest.TestCase):
    def test_library_effect_labels_restore_the_authored_fifty_language_projection(self) -> None:
        # Published v4.7.3 mir-browser values, recovered unchanged. Keep the
        # original unit distinction without inventing new translations.
        keys = ("setting-effect-per-level", "setting-effect-per-level-percent")
        projection = {}
        for path in sorted(LOCALE_ROOT.glob("*/mir-library.cfg")):
            browser = parse_cfg(path)["mir-browser"]
            projection[path.parent.name] = {key: browser[key] for key in keys}
        self.assertEqual(len(projection), 50)
        encoded = json.dumps(projection, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
        self.assertEqual(hashlib.sha256(encoded).hexdigest(),
                         "46438ef947849f25a88e809902e1bc101b07a7c86d16a5f639b400633d086e4c")
        self.assertEqual(projection["en"], {keys[0]: "Effect per level", keys[1]: "Bonus per level (%)"})
        self.assertEqual(projection["de"], {keys[0]: "Wirkung pro Level", keys[1]: "Bonus pro Level (%)"})

    def test_current_settings_have_english_names_descriptions_and_arguments(self) -> None:
        english = parse_cfg(LOCALE_ROOT / "en" / "more-infinite-research.cfg")
        for section in ("mod-setting-name", "mod-setting-description"):
            for key in NATIVE_SETTING_KEYS + STANDALONE_SETTING_KEYS:
                with self.subTest(section=section, key=key):
                    value = english.get(section, {}).get(key, "")
                    self.assertTrue(value.strip(), f"missing {section}.{key}")
                    arguments = set(re.findall(r"__(\d+)__", value))
                    self.assertEqual(arguments, {"1"} if key in NATIVE_SETTING_KEYS else set())

    def test_german_visible_option_is_shorter_and_startup_names_are_translated(self) -> None:
        # Actual R07 German images exposed the overlong Show option and six
        # missing startup names. A descriptor audit also exposed the native
        # level-1 cost label fallback. Rendered fit remains a separate check.
        browser = parse_cfg(LOCALE_ROOT / "de" / "mir-library.cfg")["mir-browser"]
        with self.subTest(case="shorter-visibility-option"):
            self.assertLess(len(browser["visibility-normal"]), len("Forschung in diesem Spiel"))
            self.assertIn("Spiel", browser["visibility-normal"])
        german = parse_cfg(LOCALE_ROOT / "de" / "more-infinite-research.cfg")["mod-setting-name"]
        english = parse_cfg(LOCALE_ROOT / "en" / "more-infinite-research.cfg")["mod-setting-name"]
        keys = (
            "mir-max-level-worker-robots-speed", "mir-adjust-vanilla-weapon-speed-techs",
            "mir-automatic-compiler-mode", "mir-automatic-create-research",
            "mir-automatic-require-reviewed-data", "mir-compiler-profile",
            "mir-cost-base",
        )
        tags = r"\[(?:/?font|/?color)(?:=[^\]]+)?\]"
        for key in keys:
            with self.subTest(key=key):
                self.assertIn(key, german)
                self.assertNotEqual(german[key], english[key])
                self.assertEqual(re.findall(tags, german[key]), re.findall(tags, english[key]))
                self.assertEqual(re.findall(r"__\d+__", german[key]), re.findall(r"__\d+__", english[key]))
        # Base 2.1.23's technology-name.worker-robots-speed, not a literal
        # translation of "worker robot" or a new gameplay identity.
        self.assertIn("Arbeitsroboter-Geschwindigkeit", german.get(keys[0], ""))
        with self.subTest(case="level-one-coefficient"):
            self.assertRegex(german.get("mir-cost-base", ""), r"Kostenkoeffizient.*Stufe 1")

    def test_german_queue_guidance_preserves_native_queue_authority(self) -> None:
        # RUN-04 and the English guidance: queue actions belong to the native
        # Technology screen. R07's German caption omitted that boundary.
        browser = parse_cfg(LOCALE_ROOT / "de" / "mir-library.cfg")["mir-browser"]
        guidance = browser["native-queue-guidance"]
        with self.subTest(case="native-screen-actions"):
            for term in ("Technologiefenster", "einreihen", "neu ordnen", "abbrechen"):
                self.assertIn(term, guidance)
        with self.subTest(case="read-only-library"):
            self.assertRegex(guidance, r"Bibliothek.*ändert.*Forschungswarteschlange.*nicht")
        # Native Core 2.1.23 translates force as Partei; this heading is in
        # the shared CFG rather than the separate Library CFG.
        common = parse_cfg(LOCALE_ROOT / "de" / "more-infinite-research.cfg")["mir-browser"]
        with self.subTest(case="native-force-term"):
            self.assertIn("Partei", common["queue"])
            self.assertNotIn("Force", common["queue"])

    def test_source_reference_coverage_is_finite_and_explicit(self) -> None:
        expected = {
            f"{section}.{key}"
            for section, keys in B6_RETAINED_KEYS.items()
            for key in keys
        }
        expected.add(f"technology-name.{NEW_ENGLISH_ONLY_KEY}")
        expected.add("technology-description.more-infinite-research.material_process_unavailable")
        self.assertEqual(active_source_references(), expected)

    def test_all_locales_restore_the_pinned_b6_projection_without_duplicates(self) -> None:
        locale_paths = sorted(LOCALE_ROOT.glob("*/more-infinite-research.cfg"))
        self.assertEqual({path.parent.name for path in locale_paths}, set(EXPECTED_RETAINED_PROJECTION_SHA256))
        for path in locale_paths:
            language = path.parent.name
            sections = parse_cfg(path)
            projection = retained_projection(sections)
            for full_key, expected in CURRENT_TRANSLATION_OVERRIDES.get(language, {}).items():
                self.assertEqual(projection[full_key], expected, f"{language}: {full_key}")
            for full_key, (corrected, historical) in ACCEPTED_POST_B6_CORRECTIONS.get(language, {}).items():
                self.assertEqual(projection[full_key], corrected, f"{language}: {full_key}")
                if full_key == DIRECT_EFFECT_KEY:
                    self.assertEqual(corrected, direct_effect_first_benefit(language, historical), language)
                projection[full_key] = historical
            actual = hashlib.sha256(
                json.dumps(projection, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
            ).hexdigest().upper()
            self.assertEqual(actual, EXPECTED_RETAINED_PROJECTION_SHA256[language], language)

    def test_mining_drill_and_material_family_labels_have_independent_historical_values(self) -> None:
        english = parse_cfg(LOCALE_ROOT / "en" / "more-infinite-research.cfg")
        german = parse_cfg(LOCALE_ROOT / "de" / "more-infinite-research.cfg")
        self.assertEqual(
            english["technology-name"]["more-infinite-research.research_mining_drill"],
            "Mining-drill manufacturing productivity",
        )
        self.assertEqual(
            german["technology-name"]["more-infinite-research.research_mining_drill"],
            "Erzförderer-Produktivität",
        )
        self.assertEqual(
            english["technology-name"]["more-infinite-research.research_steel"],
            "Steel plate productivity",
        )

    def test_hidden_k2_state_carrier_has_the_explicitly_new_english_title_only(self) -> None:
        english = parse_cfg(LOCALE_ROOT / "en" / "more-infinite-research.cfg")
        self.assertEqual(english["technology-name"][NEW_ENGLISH_ONLY_KEY], NEW_ENGLISH_ONLY_VALUE)
        for path in sorted(LOCALE_ROOT.glob("*/more-infinite-research.cfg")):
            if path.parent.name == "en":
                continue
            sections = parse_cfg(path)
            self.assertNotIn(NEW_ENGLISH_ONLY_KEY, sections.get("technology-name", {}), path.parent.name)

    def test_computed_material_family_labels_are_finite_and_english_only(self) -> None:
        self.assertEqual(computed_material_families(), set(COMPUTED_MATERIAL_ENGLISH_NAMES))
        english = parse_cfg(LOCALE_ROOT / "en" / "more-infinite-research.cfg")
        names = english["technology-name"]
        for family, expected in COMPUTED_MATERIAL_ENGLISH_NAMES.items():
            self.assertEqual(names[f"more-infinite-research.{family}"], expected, family)
        for path in sorted(LOCALE_ROOT.glob("*/more-infinite-research.cfg")):
            if path.parent.name == "en":
                continue
            names = parse_cfg(path).get("technology-name", {})
            for family in COMPUTED_MATERIAL_ENGLISH_NAMES:
                self.assertNotIn(f"more-infinite-research.{family}", names, path.parent.name)

    def test_parser_refuses_duplicate_or_conflicting_locale_keys(self) -> None:
        with self.assertRaisesRegex(ValueError, "duplicate locale key"):
            parse_cfg_text("[technology-name]\nkey=first\nkey=second\n", "synthetic")
if __name__ == "__main__":
    unittest.main()

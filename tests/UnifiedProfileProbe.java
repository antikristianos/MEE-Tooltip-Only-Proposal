import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import java.util.function.Function;
import se.krka.kahlua.converter.KahluaConverterManager;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.*;
import zombie.Lua.*;
import zombie.core.*;

public final class UnifiedProfileProbe {
    static long checks;
    static void check(boolean value, String message) { checks++; if (!value) throw new AssertionError(message); }
    static Map<String,String> load(Path slice, String locale) throws Exception {
        var constructor=Language.class.getDeclaredConstructor(String.class,String.class,String.class,boolean.class);
        constructor.setAccessible(true);
        var reader=Translator.class.getDeclaredMethod("tryFillMapFromFile",String.class,String.class,Map.class,Language.class,Function.class);
        reader.setAccessible(true);
        Map<String,String> map=new HashMap<>();
        reader.invoke(null,slice.toString(),"Moodles",map,constructor.newInstance(locale,locale,"EN",false),Function.identity());
        check(!map.isEmpty(),"native loader returned no keys: "+locale);
        return map;
    }
    public static void main(String[] args) throws Exception {
        zombie.core.random.RandStandard.INSTANCE.init(); Core.debug=false;
        Path root=Path.of(args[0]);
        Path common=root.resolve("Contents/mods/MoodleEffectsExplainedUnified/common/media/lua/client");
        Path slice=root.resolve("Contents/mods/MoodleEffectsExplainedUnified/42.20");
        var platform=J2SEPlatform.getInstance();
        var env=platform.newEnvironment();
        var thread=new KahluaThread(platform,env); thread.debugOwnerThread=Thread.currentThread();
        LuaManager.env=env; LuaManager.thread=thread;
        var converter=new KahluaConverterManager(); KahluaNumberConverter.install(converter);
        var exposer=new LuaManager.Exposer(converter,platform,env); LuaManager.exposer=exposer;
        var classes=new Class<?>[]{HashMap.class,ArrayList.class,Translator.class,Language.class};
        for(var cls:classes)exposer.setExposed(cls);
        for(var cls:classes)exposer.exposeLikeJavaRecursively(cls,env);
        var keys=thread.call(LuaCompiler.loadstring(Files.readString(common.resolve("MEE/ProfileKeys.lua")),"keys",env),new Object[0]);
        env.rawset("profileKeys",keys);
        String boot="require=function(name) return profileKeys end; MEE={}; Events={}; "
            +"for _,name in ipairs({'OnGameBoot','OnGameStart','OnCreatePlayer','OnTick'}) do "
            +"local callbacks={}; Events[name]={callbacks=callbacks,Add=function(fn) callbacks[#callbacks+1]=fn end,"
            +"Remove=function(fn) for i=#callbacks,1,-1 do if callbacks[i]==fn then table.remove(callbacks,i) end end end} end;"
            +"getActivatedMods=function() return activeMods end;";
        check(Boolean.TRUE.equals(thread.pcall(LuaCompiler.loadstring(boot,"boot",env),new Object[0])[0]),"bootstrap failed");
        check(Boolean.TRUE.equals(thread.pcall(LuaCompiler.loadstring(Files.readString(common.resolve("MEE/Profile.lua")),"profile",env),new Object[0])[0]),"profile load failed");
        var profile=(KahluaTable)((KahluaTable)env.rawget("MEE")).rawget("Profile");
        var nativeMap=Translator.BY_NAME.get("Moodles");
        var languageConstructor=Language.class.getDeclaredConstructor(String.class,String.class,String.class,boolean.class);
        languageConstructor.setAccessible(true);
        Map<String,String> owners=Map.of("Base","MoodleEffectsExplained","EM","MoodleEffectsExplained_ExpandedMoodles","DTEM","MoodleEffectsExplained_DTEM");
        String[][] combinations={{},{"ExpandedMoodles"},{"DynamicTraits"},{"ExpandedMoodles","DynamicTraits"},{"DynamicTraits","ExpandedMoodles"},{"DynamicTraitsSE"}};
        String[] expected={"Base","EM","DTEM","DTEM","DTEM","Base"};
        try(var locales=Files.list(slice.resolve("media/lua/shared/Translate"))) {
            for(Path locale:locales.sorted().toList()) {
                var generated=load(slice,locale.getFileName().toString()); nativeMap.clear(); nativeMap.putAll(generated);
                Translator.language=languageConstructor.newInstance(locale.getFileName().toString(),locale.getFileName().toString(),"EN",false);
                Map<String,Map<String,String>> originals=new HashMap<>();
                for(var item:owners.entrySet()) originals.put(item.getKey(),load(root.resolve("upstream/"+item.getValue()+"/42.20"),locale.getFileName().toString()));
                for(int scenario=0;scenario<combinations.length;scenario++) {
                    env.rawset("activeMods",new ArrayList<>(Arrays.asList(combinations[scenario])));
                    var result=thread.pcall(profile.rawget("apply"),new Object[0]);
                    check(Boolean.TRUE.equals(result[0]) && Boolean.TRUE.equals(result[1]),"public Translator map apply failed: "+Arrays.toString(result));
                    check(expected[scenario].equals(profile.rawget("selected")),"wrong profile for combination");
                    for(var entry:originals.get(expected[scenario]).entrySet()) {
                        check(entry.getValue().equals(nativeMap.get(entry.getKey())),"original string/escape changed: "+locale+" "+entry.getKey());
                    }
                    check(Translator.getText("Moodles_Hungry_desc_lvl1").equals(Translator.getText(
                        "Moodles_MEEProfile_"+expected[scenario]+"_Moodles_Hungry_desc_lvl1")),"native percent/line formatting changed");
                }
                // One deferred application after foreign startup handlers must win
                // without registering a persistent tick poll.
                env.rawset("activeMods",new ArrayList<>(List.of("ExpandedMoodles","DynamicTraits")));
                var lifecycle=thread.pcall(LuaCompiler.loadstring("MEE.Profile.refresh(); local callbacks=Events.OnTick.callbacks; "
                    +"for i=#callbacks,1,-1 do callbacks[i]() end; assert(#Events.OnTick.callbacks==0)","lifecycle",env),new Object[0]);
                check(Boolean.TRUE.equals(lifecycle[0]),"deferred startup did not tear down");
                var removed=nativeMap.remove("Moodles_MEEProfile_DTEM_Moodles_Hungry_desc_lvl1");
                var before=new HashMap<>(nativeMap);
                var missing=thread.pcall(profile.rawget("apply"),new Object[0]);
                check(Boolean.TRUE.equals(missing[0]) && Boolean.FALSE.equals(missing[1]),"missing profile did not fail safely");
                check(before.equals(nativeMap),"partial translation writes on missing profile");
                nativeMap.put("Moodles_MEEProfile_DTEM_Moodles_Hungry_desc_lvl1",removed);
                System.out.println("PASS native Translator + Kahlua profiles: "+locale.getFileName()+", all 6 activation combinations");
            }
        }
        System.out.println("PASS unified profiles: "+checks+" assertions; original text preserved; both companion orders -> DTEM; no debug/reflection in production.");
    }
}

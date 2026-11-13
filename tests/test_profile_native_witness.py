"""Read-only native witness and wrong-output opponents; no native acceptance."""
import argparse
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ProfileNativeWitnessTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.globals().witness_path = (ROOT / "tests/fixtures/profile-native-witness/witness.lua").as_posix()
        self.lua.execute('''
          W = dofile(witness_path)
          function independent_world(base,mode)
            local f210=base=="2.1.23"
            local product={type="item",name="iron-ore",amount=1}
            product[f210 and "independent_probability" or "probability"]=mode=="aliases" and .25 or .1234
            local receiver={consumption_limits={low=-.8325},pollution_limits={low=-.91125},
              speed_limits={low=-.755,high=mode=="aliases" and 1000 or 12.345},
              quality_limits={high=mode=="aliases" and 1000 or 6.789}}
            local raw={recipe={["iron-gear-wheel"]={maximum_productivity=43.215},
                ["iron-ore-recycling"]={results={product}}},
              ["assembling-machine"]={["assembling-machine-2"]={fluid_boxes={{max_pipeline_extent=395}}},
                ["assembling-machine-1"]={effect_receiver=f210 and receiver or nil}}}
            local native={recipe={["iron-gear-wheel"]={maximum_productivity=43.215},
                ["iron-ore-recycling"]={products={product}}},
              entity={["assembling-machine-1"]={effect_receiver=f210 and receiver or nil}}}
            if mode=="aliases" then
              raw.recipe["iron-gear-wheel"].maximum_productivity=nil
              native.recipe["iron-gear-wheel"].maximum_productivity=3
              raw["assembling-machine"]["assembling-machine-2"].fluid_boxes[1].max_pipeline_extent=nil
              receiver.consumption_limits=nil;receiver.pollution_limits=nil
              receiver.speed_limits.low=nil
            end
            return raw,native,product,receiver
          end
          function frozen(t)
            local copy={}
            for k,v in pairs(t)do copy[k]=type(v)=="table" and frozen(v) or v end
            return copy
          end
          function same(a,b)
            assert(type(a)==type(b))
            if type(a)~="table" then assert(a==b);return end
            for k,v in pairs(a)do same(v,b[k])end
            for k in pairs(b)do assert(a[k]~=nil)end
          end
        ''')

    def test_both_engines_modes_are_read_only_and_keep_actual_numbers(self):
        self.lua.execute('''
          for _,base in ipairs({"2.0.77","2.1.23"})do
            for _,mode in ipairs({"numeric","aliases"})do
              local raw,native=independent_world(base,mode)
              local a,b=frozen(raw),frozen(native)
              local data=W.data(raw,base,mode)
              local runtime=W.runtime(native,base,mode)
              assert(runtime.pipeline_extent==nil)
              if mode=="numeric" then assert(data.pipeline_extent==395)else assert(data.pipeline_extent==nil)end
              assert(data.pipeline_extent_explicit==(mode=="numeric"))
              assert(data.receiver_limits_supported==(base=="2.1.23"))
              assert(W.line(data):find(mode=="numeric" and "pipeline=395" or "pipeline=implicit",1,true))
              same(a,raw);same(b,native)
            end
          end
        ''')

    def test_each_wrong_native_scalar_or_missing_receiver_rejects(self):
        self.lua.execute('''
          for _,mode in ipairs({"numeric","aliases"})do
            for _,field in ipairs({"speed_limits","quality_limits"})do
              local raw,native,p,r=independent_world("2.1.23",mode)
              r[field].high=0
              assert(not pcall(W.data,raw,"2.1.23",mode))
              assert(not pcall(W.runtime,native,"2.1.23",mode))
            end
            local fields=mode=="numeric" and {"consumption_limits","pollution_limits","speed_limits","quality_limits"}
              or {"speed_limits","quality_limits"}
            for _,field in ipairs(fields)do
              for _,missing in ipairs({false,true})do
                local raw,native,p,r=independent_world("2.1.23",mode)
                if missing then r[field]=nil else
                  local side=(mode=="aliases" or field=="quality_limits") and "high" or "low";r[field][side]=0
                end
                assert(not pcall(W.data,raw,"2.1.23",mode))
                assert(not pcall(W.runtime,native,"2.1.23",mode))
              end
            end
            for _,base in ipairs({"2.0.77","2.1.23"})do
              for _,bad in ipairs({0,0/0,math.huge,".1234"})do
                local raw,native,p=independent_world(base,mode)
                p[base=="2.1.23" and "independent_probability" or "probability"]=bad
                assert(not pcall(W.data,raw,base,mode))
                assert(not pcall(W.runtime,native,base,mode))
              end
              local raw,native=independent_world(base,mode)
              if mode=="numeric" then
                raw.recipe["iron-gear-wheel"].maximum_productivity=1
                native.recipe["iron-gear-wheel"].maximum_productivity=1
                assert(not pcall(W.data,raw,base,mode))
                assert(not pcall(W.runtime,native,base,mode))
              end
              raw,native=independent_world(base,mode)
              raw["assembling-machine"]["assembling-machine-2"].fluid_boxes[1].max_pipeline_extent=320
              assert(not pcall(W.data,raw,base,mode))
              for _,mutate in ipairs({
                function(p)p.name="copper-ore" end,
                function(p)p.type="fluid" end,
                function(p)p.amount=2 end,
                function(p)p.extra_count_fraction=.5 end,
              })do
                local raw,native,p=independent_world(base,mode)
                mutate(p)
                assert(not pcall(W.data,raw,base,mode))
                assert(not pcall(W.runtime,native,base,mode))
              end
              raw,native=independent_world(base,mode)
              raw.recipe["iron-ore-recycling"].results[2]={type="item",name="iron-ore",amount=1}
              assert(not pcall(W.data,raw,base,mode))
            end
          end
        ''')

    def test_observer_retains_native_float_precision_with_existing_tolerance(self):
        self.lua.execute('''
          local raw,native,p=independent_world("2.0.77","numeric")
          p.probability=.1234000027179718
          assert(W.data(raw,"2.0.77","numeric").recycling_probability==p.probability)
          assert(W.runtime(native,"2.0.77","numeric").recycling_probability==p.probability)
          assert(not pcall(W.data,raw,"2.0.78","numeric"))
          assert(not pcall(W.data,raw,"2.0.77","unknown"))
        ''')


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua-runtime-dir", type=Path, required=True)
    args = parser.parse_args()
    sys.path.insert(0, str(args.lua_runtime_dir.resolve(strict=True)))
    from lupa.lua52 import LuaRuntime
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(ProfileNativeWitnessTests))
    sys.exit(0 if result.wasSuccessful() else 1)

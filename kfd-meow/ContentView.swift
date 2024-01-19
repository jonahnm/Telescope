/*
 * Copyright (c) 2023 Félix Poulin-Bélanger. All rights reserved.
 */

import SwiftUI
import KernelPatchfinder

struct ContentView: View {
    
    @State private var result: UInt64 = 0
    private var puaf_method_options = ["physpuppet", "smith", "landa"]
    @State private var puaf_method = 2
    private var pplrw_options = ["on", "off"]
    @State private var pplrw_toggle = 1
    @State private var message = ""
    @State private var action = "overwrite"
    @State private var overwritten = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextEditor(text: $message)
                        .disabled(true)
                        .font(Font(UIFont.monospacedSystemFont(ofSize: 11.0, weight: .regular)))
                        .frame(height: 180)
                    Picker(selection: $puaf_method, label: Text("puaf method:")) {
                        ForEach(0 ..< puaf_method_options.count, id: \.self) {
                            Text(self.puaf_method_options[$0])
                        }
                    }.disabled(result != 0).pickerStyle(SegmentedPickerStyle())
                    Picker(selection: $pplrw_toggle, label: Text("pplrw:")) {
                        ForEach(0 ..< pplrw_options.count, id: \.self) {
                            Text(self.pplrw_options[$0])
                        }
                    }.disabled(result != 0).pickerStyle(SegmentedPickerStyle())
                }
                Section {
                    HStack {
                        Button("kopen") {
                            message = ""
                            result = kpoen_bridge(UInt64(puaf_method), UInt64(pplrw_toggle))
                            if (result != 0) {
                                message = "[*] kopened\n[*] kslide: " + String(get_kernel_slide(), radix:16) + "\n"
                            }
                        }.disabled(result != 0).frame(minWidth: 0, maxWidth: .infinity)
                        Button("kclose") {
                            result = meow_and_kclose(result)
                            if (result == 0) {
                                message = message + "[*] kclosed"
                            }
                        }.disabled(result == 0).frame(minWidth: 0, maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }.listRowBackground(Color.clear)
                Section 
                {
                    Button("Start Telescope") {
                        let result = load_telescope()
                        if(result == 0) {
                            message = message + "[!] Trustcache is too short\n"
                        } else if(result == 1) {
                            message = message + "[!] Trustcache version is invalid\n"
                        } else if(result == 2) {
                            message = message + "[!] Something is wrong with count\n"
                        }else if(result == 3) {
                            message = message + "[!] find_pmap_image4_trust_caches returned 0x0\n"
                        } else if(result == 4) {
                            message = message + "[!] Telescopeinit was killed via a signal.\n"
                        } else if(result == 5) {
                            message = message + "[!] Mem is 0\n"
                        }
                        else {
                            message = message + "[*] Suceeded to start Telescoped\n"
                        }
                    }.buttonStyle(.bordered)
                    Button("Test KALLOC") {
                        let addr = testKalloc()
                        message = message + String(format: "Kalloc'ed to: %p",addr)
                    }.buttonStyle(.bordered)
                    Button("TEST TCINJECTION") {
                        tcinjecttest()
                    }.buttonStyle(.bordered)
                }.listRowBackground(Color.clear)
                
            }
        }
    }
}

#Preview {
    ContentView()
}

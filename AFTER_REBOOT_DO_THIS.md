 After reboot, do this:                                                                                
                                                                                                        
  # 1. Verify KVM (MUST see "kvm" in output!)                                                           
  groups | grep kvm                                                                                     
                                                                                                        
  # 2. Navigate to project                                                                              
  cd /home/jjj/test_oskeyring                                                                           
                                                                                                        
  # 3. Provision VM (takes 5-10 min, downloads Ubuntu)                                                  
  cd ansible                                                                                            
  ansible-playbook playbooks/vm-provision.yml                                                           
  cd ..                                                                                                 
                                                                                                        
  # 4. Run tests                                                                                        
  ./scripts/run-orchestration.sh                                                                        
                                                                                                        
  Expected result: All 4 consumers pass, including consumer-ubuntu (the VM!)                            
                                                                                                        
  Which Document to Read First?                                                                         
                                                                                                        
  - Want checklist format? → CHECKLIST.md                                                               
  - Want detailed step-by-step? → POST_REBOOT_INSTRUCTIONS.md (most comprehensive)                      
  - Want quick reminder? → RESUME_HERE.txt                                                              
  - Unsure which to read? → START_HERE.md                                                               
                                                                                                        
  Key Points Documented                                                                                 
                                                                                                        
  ✅ Reboot required - Clearly stated in all docs                                                       
  ✅ KVM group verification - First check in all docs                                                   
  ✅ Exact commands to run - With expected outputs                                                      
  ✅ vm-ctl.sh capabilities - Documented with examples                                                  
  ✅ Troubleshooting steps - Decision trees for common issues                                           
  ✅ Timeline expectations - How long each step takes                                                   
  ✅ Success criteria - What passing tests look like                                                    
                                                                                                        
  Everything is documented with minimal disruption in mind. You can pick up exactly where we left off!  
 

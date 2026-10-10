-- Hidden compatibility identities remain inspectable and can retain an old
-- queue entry, but the Library must not offer to start new research in them.
return function(catalogue, actions, check, host)
  local force={valid=true,index=991,name="hidden-regression",research_enabled=true,technologies={},research_queue={}}
  local tech={valid=true,name="retained",force=force,enabled=true,researched=false,prerequisites={},
    prototype={hidden=false,max_level="infinite",order=""}}
  force.technologies.retained=tech
  local player={valid=true,force=force}
  check(catalogue.snapshot(force,host).rows[1].available,"visible unresearched technology is available")
  check(actions.can_enqueue(player,tech,1),"visible unresearched technology can be queued")
  tech.prototype.hidden=true
  check(not catalogue.snapshot(force,host).rows[1].available,"hidden identity is not offered as available research")
  check(not actions.can_enqueue(player,tech,1),"hidden identity cannot start new research")
  force.research_queue={tech}
  local row=catalogue.snapshot(force,host).rows[1]
  check(row.key==tech.name and row.queued and not row.available,"existing hidden queue entry remains inspectable")
  check(force.research_queue[1]==tech and tech.enabled and not tech.researched,"availability checks preserve queued research")
  tech.prototype.hidden=false
  force.research_queue={}
  check(catalogue.snapshot(force,host).rows[1].available and actions.can_enqueue(player,tech,1),"visible research becomes available again")
  catalogue.forget_force(force.index)
end

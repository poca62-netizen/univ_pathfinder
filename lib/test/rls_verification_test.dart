// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
// ignore: depend_on_referenced_packages
import 'package:supabase/supabase.dart';

Future<void> main() async {
  final env = jsonDecode(File('.env.dev.json').readAsStringSync()) as Map;
  final url = env['SUPABASE_URL'] as String;
  final anonKey = env['SUPABASE_PUBLISHABLE_KEY'] as String;
  SupabaseClient? clientA; SupabaseClient? clientB; int passed=0; int total=0;
  Future<bool> test(String n, Future<bool> Function() fn) async {
    total++; try { final ok=await fn(); if(ok) passed++; print('${ok?"PASS":"FAIL"}: $n'); return ok; } catch(e){ print('FAIL: $n - $e'); return false; }
  }
  try {
    clientA=SupabaseClient(url,anonKey); clientB=SupabaseClient(url,anonKey);
    await clientA.auth.signInAnonymously(); await clientB.auth.signInAnonymously();
    final uidA=clientA.auth.currentUser?.id; final uidB=clientB.auth.currentUser?.id;
    if(uidA==null||uidB==null){ print('FAIL auth'); return; }
    await test('UID distinct', ()=>Future.value(uidA!=uidB));
    final nick='test_${DateTime.now().millisecondsSinceEpoch}'; String? gid;
    await test('A profiles INSERT', ()=>clientA!.from('profiles').insert({'id':uidA,'nickname':nick}).then((_)=>true));
    await test('A profiles SELECT', ()=>clientA!.from('profiles').select('nickname').eq('id',uidA).single().then((r)=>r['nickname']==nick));
    await test('A profiles UPDATE', ()=>clientA!.from('profiles').update({'nickname':'${nick}_u'}).eq('id',uidA).select().then((_)=>clientA!.from('profiles').select('nickname').eq('id',uidA).single().then((r)=>r['nickname']=='${nick}_u')));
    await test('A grade INSERT', ()=>clientA!.from('grade_records').insert({'user_id':uidA,'school_year':1,'semester':1,'subject_name':'국어','credit':2,'raw_score':85,'subject_average':80,'achievement':'A','grade_rank':2,'achievement_distribution':{'A':40,'B':30,'C':20,'D':10,'E':0}}).select().single().then((r){gid=r['id'] as String; return gid!=null;}));
    await test('A grade exists', ()=>clientA!.from('grade_records').select('id').eq('id',gid!).maybeSingle().then((r)=>r!=null));
    await test('A grade SELECT', ()=>clientA!.from('grade_records').select('subject_name').eq('id',gid!).single().then((r)=>r['subject_name']=='국어'));
    await test('A grade UPDATE', ()=>clientA!.from('grade_records').update({'raw_score':86}).eq('id',gid!).select().then((_)=>clientA!.from('grade_records').select('raw_score').eq('id',gid!).single().then((r)=>r['raw_score']==86)));
    await test('B SELECT A profiles 0', ()=>clientB!.from('profiles').select('id').eq('id',uidA).then((r)=>r.isEmpty));
    await test('B SELECT A grades 0', ()=>clientB!.from('grade_records').select('id').eq('user_id',uidA).then((r)=>r.isEmpty));
    await test('B UPDATE blocked', () async {
      final u = await clientB!.from('grade_records').update({'raw_score':99}).eq('id',gid!).select();
      if (u.isNotEmpty) return false;
      final r = await clientA!.from('grade_records').select('raw_score').eq('id',gid!).single();
      return r['raw_score']==86;
    });
    await test('B DELETE blocked', () async {
      final d = await clientB!.from('grade_records').delete().eq('id',gid!).select();
      if (d.isNotEmpty) return false;
      final r = await clientA!.from('grade_records').select('id').eq('id',gid!).maybeSingle();
      return r != null;
    });
    await test('B INSERT RLS 42501', ()=>Future(() async { try{ await clientB!.from('grade_records').insert({'user_id':uidA,'school_year':1,'semester':1,'subject_name':'수학','credit':2}); return false; } on PostgrestException catch(e){ return e.code=='42501'; }}));
    await test('Unauth SELECT blocked', ()=>Future(() async { final u=SupabaseClient(url,anonKey); try{ final r=await u.from('grade_records').select('id').eq('user_id',uidA); return r.isEmpty; } on PostgrestException catch(e){ return e.code=='401'||e.code=='PGRST301'; } catch(_){ return false; }}));
    Future<bool> check(Map<String,dynamic> d)=>Future(() async { try{ await clientA!.from('grade_records').insert(d); return false; } on PostgrestException catch(e){ return e.code=='23514'; }});
    await test('CHECK school_year', ()=>check({'user_id':uidA,'school_year':4,'semester':1,'subject_name':'X','credit':1}));
    await test('CHECK semester', ()=>check({'user_id':uidA,'school_year':1,'semester':3,'subject_name':'X','credit':1}));
    await test('CHECK credit', ()=>check({'user_id':uidA,'school_year':1,'semester':1,'subject_name':'X','credit':0}));
    await test('CHECK raw_score', ()=>check({'user_id':uidA,'school_year':1,'semester':1,'subject_name':'X','credit':1,'raw_score':150}));
    await test('CHECK subject_average', ()=>check({'user_id':uidA,'school_year':1,'semester':1,'subject_name':'X','credit':1,'subject_average':-1}));
    await test('CHECK grade_rank', ()=>check({'user_id':uidA,'school_year':1,'semester':1,'subject_name':'X','credit':1,'grade_rank':6}));
    await test('CHECK distribution', ()=>check({'user_id':uidA,'school_year':1,'semester':1,'subject_name':'X','credit':1,'achievement_distribution':{'A':'bad'}}));
    await test('A grade DELETE', ()=>clientA!.from('grade_records').delete().eq('id',gid!).select().then((d)=>d.isNotEmpty));
    print('Summary: $passed/$total passed');
  } finally {
    try { if(clientA!=null){ final uid=clientA.auth.currentUser?.id; if(uid!=null) await clientA.from('profiles').delete().eq('id',uid).select(); } } catch(_){}
    clientA=null; clientB=null;
  }
}


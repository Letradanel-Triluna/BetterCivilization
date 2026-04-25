// FAutoVariableBase_compat.cpp
//
// Replacement implementations of FAutoVariableBase and FAutoArchive methods for
// FINAL_RELEASE builds linked against FireWorksWin32.lib (compiled without FINAL_RELEASE).
//
// Problem: FireWorksWin32.lib was compiled without FINAL_RELEASE, so its methods assume
// FAutoVariableBase objects are ~56 bytes (vtable + FCallStack + std::string + bool debug
// members). Our FINAL_RELEASE build omits those members (object is 4 bytes: vtable only).
//
// The lib's FAutoVariableBase constructor, FAutoArchive::add(), and FAutoVariableBase
// debug methods all access those missing members -> heap/memory corruption -> crash.
//
// Fix: Override all affected methods here via /FORCE:MULTIPLE.
//   - Constructors/destructor: initialize without touching non-existent debug members
//   - FAutoArchive::add: push to m_contents + register name; NO debug member writes
//   - FAutoArchive::remove: erase from m_contents and m_deltas safely
//   - FAutoVariableBase debug accessors: return empty strings (safe no-ops)
//
// This file must be compiled with FINAL_RELEASE defined (inherited from project settings).

// Use direct Windows headers only - avoid PCH ordering issues for this file
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string>
#include <vector>
#include <set>
#include <algorithm>
#include <utility>

// Pull in FireWorks headers directly (not through PCH) to get class declarations
#include "FireWorks/FAutoVariableBase.h"
#include "FireWorks/FAutoArchive.h"

// ============================================================
// FAutoVariableBase constructors / destructor
// ============================================================

FAutoVariableBase::FAutoVariableBase(const std::string& name, FAutoArchive& owner)
{
	// Register in the archive's contents list
	owner.add(*this);
	// Register the variable's name so that name() works correctly.
	// Must be called after add() so *this is findable in m_contents.
	// Calling setVariableName on a fully-constructed owner is safe via virtual dispatch.
	owner.setVariableName(*this, name);
}

FAutoVariableBase::FAutoVariableBase(const std::string& name, FAutoArchive& owner, bool /*callStackTracking*/)
{
	owner.add(*this);
	owner.setVariableName(*this, name);
}

FAutoVariableBase::~FAutoVariableBase()
{
	// FINAL_RELEASE: no debug members to destroy
}

// ============================================================
// FAutoArchive::add / remove  (safe FINAL_RELEASE versions)
//
// The lib's add() was compiled with FAUTOARCHIVE_DEBUG and writes
//   var.m_callStackTracking = AreCallStacksEnabled();
// at offset ~132 bytes past the vtable pointer.  For our 4-byte
// FINAL_RELEASE objects that offset lands in adjacent memory ->
// heap corruption.  Our version skips that write entirely.
// ============================================================

void FAutoArchive::add(FAutoVariableBase& var)
{
	m_contents.push_back(&var);
	// FINAL_RELEASE: do NOT write var.m_callStackTracking or any other debug member
}

void FAutoArchive::remove(FAutoVariableBase& var)
{
	std::vector<FAutoVariableBase*>::iterator it =
		std::find(m_contents.begin(), m_contents.end(), &var);
	if (it != m_contents.end())
		m_contents.erase(it);
	m_deltas.erase(&var);
}

// ============================================================
// FAutoVariableBase debug accessors: safe no-ops in FINAL_RELEASE
//
// The lib versions access m_callStackRemark, m_lastCallStackToChangeThisVariable,
// m_callStackTracking which don't exist in our layout.
// ============================================================

std::string FAutoVariableBase::getStackTrace() const
{
	return std::string();
}

std::string FAutoVariableBase::getStackTraceRemark() const
{
	return std::string();
}

std::string FAutoVariableBase::debugDump(const std::vector<std::pair<std::string, std::string> >& /*callStacks*/) const
{
	return std::string();
}

// ============================================================
// FAutoArchive methods - full VS2013-layout-aware overrides
//
// Root cause: VS2008 std::vector<> is 16 bytes (explicit allocator member);
// VS2013 std::vector<> is 12 bytes (EBO - empty base optimization).
// FAutoArchive has m_contents (vector) and m_deltas (set) as members.
// When VS2008 lib code accesses these it uses VS2008 offsets, which are wrong
// for our VS2013-built DLL layout -> garbage pointers -> crash.
//
// Fix: override every non-inline FAutoArchive method here so that
// VS2008 lib implementations are never called against our VS2013 objects.
// /FORCE:MULTIPLE in the linker selects our definitions over the lib's.
// ============================================================

void FAutoArchive::reset()
{
	for (size_t i = 0; i < m_contents.size(); ++i)
		m_contents[i]->reset();
}

void FAutoArchive::clearDelta()
{
	m_deltas.clear();
	for (size_t i = 0; i < m_contents.size(); ++i)
		m_contents[i]->clearDelta();
}

bool FAutoArchive::hasDeltas() const
{
	return !m_deltas.empty();
}

void FAutoArchive::load(FDataStream& loadFrom)
{
	for (size_t i = 0; i < m_contents.size(); ++i)
		m_contents[i]->load(loadFrom);
}

void FAutoArchive::save(FDataStream& saveTo) const
{
	for (size_t i = 0; i < m_contents.size(); ++i)
		m_contents[i]->save(saveTo);
}

void FAutoArchive::loadDelta(FDataStream& loadFrom)
{
	for (size_t i = 0; i < m_contents.size(); ++i)
		m_contents[i]->loadDelta(loadFrom);
}

void FAutoArchive::saveDelta(FDataStream& saveTo, std::vector<std::pair<std::string, std::string> >& /*callStacks*/) const
{
	std::set<FAutoVariableBase*>::const_iterator it;
	for (it = m_deltas.begin(); it != m_deltas.end(); ++it)
		(*it)->saveDelta(saveTo);
}

std::vector<const FAutoVariableBase*> FAutoArchive::findMismatchedVariables(FDataStream& /*stream*/) const
{
	// OOS debug stub - not needed in FINAL_RELEASE
	return std::vector<const FAutoVariableBase*>();
}

const FAutoVariableBase* FAutoArchive::findVariable(const std::string& varName) const
{
	for (size_t i = 0; i < m_contents.size(); ++i)
	{
		if (getVariableName(*m_contents[i]) && *getVariableName(*m_contents[i]) == varName)
			return m_contents[i];
	}
	return NULL;
}
